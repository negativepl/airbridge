import Foundation
import Network
import Networking
import Mirror
import CoreMedia
import Observation

// Swift 6 strict concurrency: CMSampleBuffer's Sendable conformance is unavailable on macOS.
// Box it so it can cross actor/Task boundaries safely (all actual usage is @MainActor).
private struct UncheckedSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

@Observable @MainActor
public final class MirrorService {

    public private(set) var isStreaming: Bool = false
    public private(set) var actualPort: UInt16?

    /// AsyncStream of decoded CMSampleBuffers; consume from `@MainActor` context only.
    public let sampleBufferStream: AsyncStream<CMSampleBuffer>
    private let _continuation: AsyncStream<UncheckedSampleBuffer>.Continuation
    private let _innerStream: AsyncStream<UncheckedSampleBuffer>

    private let server: WebSocketServer
    private var pairingTokenProvider: () -> Data?
    private var decoder: VideoDecoder?

    public init(pairingTokenProvider: @escaping () -> Data? = { nil }) {
        self.pairingTokenProvider = pairingTokenProvider
        self.server = WebSocketServer(port: 8766)

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
    }

    public func stop() async {
        await server.disconnectAllClients()
        actualPort = nil
        isStreaming = false
        decoder = nil
    }

    private func handleBinaryFrame(_ data: Data) {
        do {
            let msg = try MirrorMessage.decode(data)
            switch msg {
            case let .hello(token, _, _, _):
                guard let expected = pairingTokenProvider(), token == expected else {
                    Task { await server.disconnectAllClients() }
                    return
                }
                // Reply with HELLO_ACK at fixed defaults (1080p60, 12 Mbps, keyframe 2s).
                // Quality picker / RECONFIGURE is Plan B.
                let ack = MirrorMessage.helloAck(
                    targetBitrateBps: 12_000_000,
                    fps: 60,
                    keyframeIntervalSeconds: 2,
                    targetWidth: 1920,
                    targetHeight: 1080
                )
                Task { try? await server.broadcastBinary(ack.encode()) }

            case let .videoConfig(sps, pps):
                let dec = VideoDecoder { [weak self] sample in
                    // Box CMSampleBuffer to cross the @Sendable Task boundary safely.
                    let box = UncheckedSampleBuffer(value: sample)
                    self?._continuation.yield(box)
                }
                try dec.configure(sps: sps, pps: pps)
                self.decoder = dec
                self.isStreaming = true

            case let .videoFrame(pts, naluBytes):
                guard let decoder else { return }
                // Phone sends one VIDEO_FRAME per NALU. Convert Annex-B-stripped NALU to AVCC by prepending 4-byte length.
                let avcc = NALUParser.toAVCC(naluBytes)
                try decoder.decode(avccFrame: avcc, presentationTimestampUs: pts)

            case .status, .helloAck:
                // Status logging is in Plan B; HELLO_ACK is server→client only — ignore if received.
                break
            }
        } catch {
            // Decode error → ignore frame, will recover on next keyframe.
        }
    }

    private func handleDisconnect() {
        isStreaming = false
        decoder = nil
    }
}
