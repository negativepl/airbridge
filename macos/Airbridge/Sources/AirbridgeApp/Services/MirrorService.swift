import Foundation
import Network
import Networking
import Mirror
import CoreMedia
import Observation

private enum MirrorDebugLog {
    static let url = URL(fileURLWithPath: "/tmp/airbridge-mirror.log")

    static func write(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

// Swift 6 strict concurrency: CMSampleBuffer's Sendable conformance is unavailable on macOS.
// Box it so it can cross actor/Task boundaries safely (all actual usage is @MainActor).
private struct UncheckedSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

@Observable @MainActor
public final class MirrorService {
    public static let requestedFramesPerSecond: Int = 120
    public static let requestedBitrateBps: Int = 20_000_000

    public private(set) var isStreaming: Bool = false
    public private(set) var actualPort: UInt16?
    public private(set) var remoteScreenWidth: CGFloat = 540
    public private(set) var remoteScreenHeight: CGFloat = 1170
    public private(set) var videoWidth: CGFloat = 540
    public private(set) var videoHeight: CGFloat = 1170
    public private(set) var targetStreamWidth: Int = 540
    public private(set) var targetStreamHeight: Int = 1170
    public private(set) var requestedFramesPerSecond: Int = MirrorService.requestedFramesPerSecond
    public private(set) var requestedBitrateBps: Int = MirrorService.requestedBitrateBps
    public private(set) var decodedFramesPerSecond: Double = 0
    public private(set) var incomingBitrateMbps: Double = 0
    public var remoteAspectRatio: CGFloat {
        max(remoteScreenWidth, 1) / max(remoteScreenHeight, 1)
    }
    public var videoAspectRatio: CGFloat {
        max(videoWidth, 1) / max(videoHeight, 1)
    }

    /// AsyncStream of decoded CMSampleBuffers; consume from `@MainActor` context only.
    public let sampleBufferStream: AsyncStream<CMSampleBuffer>
    private let _continuation: AsyncStream<UncheckedSampleBuffer>.Continuation
    private let _innerStream: AsyncStream<UncheckedSampleBuffer>

    private let server: WebSocketServer
    private var pairingTokenProvider: () -> Data?
    private var decoder: VideoDecoder?
    private var frameCounter = 0
    private var bitrateWindowStartedAt = Date()
    private var bitrateByteCount = 0
    private var fpsWindowStartedAt = Date()
    private var fpsFrameCount = 0

    public init(port: UInt16 = 8767, pairingTokenProvider: @escaping () -> Data? = { nil }) {
        self.pairingTokenProvider = pairingTokenProvider
        self.server = WebSocketServer(port: port)

        // Build the inner stream that can safely cross concurrency boundaries.
        var cont: AsyncStream<UncheckedSampleBuffer>.Continuation!
        let inner = AsyncStream<UncheckedSampleBuffer> { cont = $0 }
        self._continuation = cont
        self._innerStream = inner

        // Map to the public CMSampleBuffer stream (consumed exclusively on @MainActor).
        self.sampleBufferStream = AsyncStream<CMSampleBuffer> { outerCont in
            Task { @MainActor in
                for await box in inner {
                    outerCont.yield(box.value)
                }
                outerCont.finish()
            }
        }
    }

    public func setPairingTokenProvider(_ provider: @escaping () -> Data?) {
        self.pairingTokenProvider = provider
    }

    public func start() async throws {
        guard actualPort == nil else { return }
        await server.setCallbacks(
            onMessage: nil,
            onBinaryMessage: { [weak self] data in
                Task { @MainActor in self?.handleBinaryFrame(data) }
            },
            onClientConnected: { _ in },
            onClientDisconnected: { [weak self] _ in
                Task { @MainActor in self?.handleDisconnect() }
            }
        )
        try await server.start()
        actualPort = await server.actualPort
        MirrorDebugLog.write("mirror server started on port \(actualPort ?? 0)")
    }

    public func stop() async {
        await server.disconnectAllClients()
        actualPort = nil
        isStreaming = false
        decoder = nil
        frameCounter = 0
        decodedFramesPerSecond = 0
        incomingBitrateMbps = 0
        videoWidth = remoteScreenWidth
        videoHeight = remoteScreenHeight
        bitrateWindowStartedAt = Date()
        bitrateByteCount = 0
        fpsWindowStartedAt = Date()
        fpsFrameCount = 0
        MirrorDebugLog.write("mirror server stopped")
    }

    private func handleBinaryFrame(_ data: Data) {
        do {
            let msg = try MirrorMessage.decode(data)
            switch msg {
            case let .hello(token, screenWidth, screenHeight, _):
                MirrorDebugLog.write("received HELLO tokenBytes=\(token.count)")
                guard let expected = pairingTokenProvider(), token == expected else {
                    MirrorDebugLog.write("HELLO rejected")
                    Task { await server.disconnectAllClients() }
                    return
                }
                remoteScreenWidth = CGFloat(screenWidth)
                remoteScreenHeight = CGFloat(screenHeight)
                let target = nativeStreamSize(for: CGSize(width: remoteScreenWidth, height: remoteScreenHeight))
                targetStreamWidth = Int(target.width)
                targetStreamHeight = Int(target.height)
                let ack = MirrorMessage.helloAck(
                    targetBitrateBps: UInt32(requestedBitrateBps),
                    fps: UInt8(requestedFramesPerSecond),
                    keyframeIntervalSeconds: 2,
                    targetWidth: UInt32(targetStreamWidth),
                    targetHeight: UInt32(targetStreamHeight)
                )
                bitrateWindowStartedAt = Date()
                bitrateByteCount = 0
                fpsWindowStartedAt = Date()
                fpsFrameCount = 0
                MirrorDebugLog.write("sending HELLO_ACK bitrate=\(requestedBitrateBps) fps=\(requestedFramesPerSecond) size=\(targetStreamWidth)x\(targetStreamHeight) aspect=\(remoteScreenWidth)x\(remoteScreenHeight)")
                Task { try? await server.broadcastBinary(ack.encode()) }
            case let .videoConfig(sps, pps):
                MirrorDebugLog.write("received VIDEO_CONFIG sps=\(sps.count) pps=\(pps.count)")
                let dec = VideoDecoder { [weak self] sample in
                    let box = UncheckedSampleBuffer(value: sample)
                    Task { @MainActor in
                        guard let self else { return }
                        self.frameCounter += 1
                        self.updateDecodedFPS()
                        if self.frameCounter <= 10 || self.frameCounter.isMultiple(of: 60) {
                            MirrorDebugLog.write("decoded sample #\(self.frameCounter)")
                        }
                        self._continuation.yield(box)
                    }
                }
                let dims = try dec.configure(sps: sps, pps: pps)
                videoWidth = CGFloat(dims.width)
                videoHeight = CGFloat(dims.height)
                self.decoder = dec
                self.isStreaming = true

            case let .videoFrame(pts, naluBytes):
                guard let decoder else { return }
                // MediaCodec may output a full access unit with multiple Annex-B NALUs.
                // Convert the whole payload to AVCC rather than assuming a single NALU.
                let avcc = NALUParser.accessUnitToAVCC(naluBytes)
                updateIncomingBitrate(frameBytes: naluBytes.count)
                if frameCounter < 5 {
                    MirrorDebugLog.write("received VIDEO_FRAME pts=\(pts) raw=\(naluBytes.count) avcc=\(avcc.count) prefix=\(Array(naluBytes.prefix(8)))")
                }
                try decoder.decode(avccFrame: avcc, presentationTimestampUs: pts)

            case .inputTap:
                break

            case .status, .helloAck:
                // Status logging is in Plan B; HELLO_ACK is server→client only — ignore if received.
                break
            }
        } catch {
            MirrorDebugLog.write("mirror error: \(error)")
        }
    }

    private func handleDisconnect() {
        isStreaming = false
        decoder = nil
        frameCounter = 0
        decodedFramesPerSecond = 0
        incomingBitrateMbps = 0
        videoWidth = remoteScreenWidth
        videoHeight = remoteScreenHeight
        bitrateWindowStartedAt = Date()
        bitrateByteCount = 0
        fpsWindowStartedAt = Date()
        fpsFrameCount = 0
        MirrorDebugLog.write("mirror client disconnected")
    }

    public func sendTap(xNorm: CGFloat, yNorm: CGFloat) {
        let x = Float32(max(0, min(1, xNorm)))
        let y = Float32(max(0, min(1, yNorm)))
        Task {
            try? await server.broadcastBinary(MirrorMessage.inputTap(xNorm: x, yNorm: y).encode())
        }
    }

    private func nativeStreamSize(for remoteSize: CGSize) -> CGSize {
        let width = max(remoteSize.width, 1)
        let height = max(remoteSize.height, 1)

        func even(_ value: CGFloat) -> Int {
            let rounded = Int(value.rounded(.toNearestOrAwayFromZero))
            return rounded - (rounded % 2)
        }

        let nativeWidth = max(320, even(width))
        let nativeHeight = max(320, even(height))
        return CGSize(width: nativeWidth, height: nativeHeight)
    }

    private func updateIncomingBitrate(frameBytes: Int) {
        bitrateByteCount += frameBytes
        let elapsed = Date().timeIntervalSince(bitrateWindowStartedAt)
        guard elapsed >= 1 else { return }

        incomingBitrateMbps = (Double(bitrateByteCount) * 8 / elapsed) / 1_000_000
        bitrateWindowStartedAt = Date()
        bitrateByteCount = 0
    }

    private func updateDecodedFPS() {
        fpsFrameCount += 1
        let elapsed = Date().timeIntervalSince(fpsWindowStartedAt)
        guard elapsed >= 1 else { return }

        decodedFramesPerSecond = Double(fpsFrameCount) / elapsed
        fpsWindowStartedAt = Date()
        fpsFrameCount = 0
    }
}
