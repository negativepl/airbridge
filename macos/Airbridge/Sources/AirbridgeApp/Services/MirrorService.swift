import Foundation
import Network
// SecIdentity is immutable and thread-safe but not marked Sendable in the SDK;
// @preconcurrency downgrades the (false-positive) actor-crossing diagnostics.
@preconcurrency import Security
import Networking
import Mirror
import CoreMedia
import CoreGraphics
import Observation

/// Per-mode mirror quality. Each mirror mode keeps its own settings.
public struct MirrorQuality: Sendable, Equatable {
    public var fps: Int
    public var bitrateBps: Int
    public var bitrateAuto: Bool
    /// Only meaningful for the forward (phone -> Mac) mode.
    public var resolutionScale: Double
    /// H.265/HEVC instead of H.264 — better quality per bit, lower latency.
    public var useHEVC: Bool
    public init(fps: Int, bitrateBps: Int, bitrateAuto: Bool, resolutionScale: Double, useHEVC: Bool = false) {
        self.fps = fps; self.bitrateBps = bitrateBps
        self.bitrateAuto = bitrateAuto; self.resolutionScale = resolutionScale
        self.useHEVC = useHEVC
    }
}

/// The three independent mirror modes, each with its own `MirrorQuality`.
public enum MirrorSlot: Int, CaseIterable, Sendable {
    case forward = 0         // phone -> Mac
    case reverseMirror = 1   // Mac main screen -> phone
    case reverseVirtual = 2  // virtual display -> phone
}

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
    static let defaultQuality = MirrorQuality(fps: 60, bitrateBps: 20_000_000, bitrateAuto: true, resolutionScale: 1.0)

    public private(set) var isStreaming: Bool = false
    /// True while we're sending OUR screen to the phone (reverse mirror).
    public private(set) var isReverseStreaming: Bool = false
    /// True while the standalone Mirror window is showing the stream. The tab
    /// shows a placeholder instead of rendering the same stream twice (frames
    /// are fanned out per renderer, so this is a UX choice, not a constraint).
    public var presentedInWindow: Bool = false
    public private(set) var actualPort: UInt16?
    public private(set) var remoteScreenWidth: CGFloat = 540
    public private(set) var remoteScreenHeight: CGFloat = 1170
    public private(set) var videoWidth: CGFloat = 540
    public private(set) var videoHeight: CGFloat = 1170
    public private(set) var targetStreamWidth: Int = 540
    public private(set) var targetStreamHeight: Int = 1170
    public static let fpsKey = "mirrorRequestedFps"
    public static let bitrateKey = "mirrorRequestedBitrateBps"
    public static let bitrateAutoKey = "mirrorBitrateAuto"
    public static let resolutionScaleKey = "mirrorResolutionScale"

    /// Per-mode quality, persisted. Applied on the NEXT start of that mode
    /// (HELLO_ACK / reverse pipeline), not mid-stream.
    public private(set) var quality: [Int: MirrorQuality] = [:]

    public func quality(_ slot: MirrorSlot) -> MirrorQuality {
        quality[slot.rawValue] ?? Self.defaultQuality
    }
    public func setQuality(_ slot: MirrorSlot, _ q: MirrorQuality) {
        quality[slot.rawValue] = q
        Self.persist(slot, q)
    }

    private static func persist(_ slot: MirrorSlot, _ q: MirrorQuality) {
        let d = UserDefaults.standard, p = "mirrorQ.\(slot.rawValue)."
        d.set(q.fps, forKey: p + "fps")
        d.set(q.bitrateBps, forKey: p + "bitrate")
        d.set(q.bitrateAuto, forKey: p + "auto")
        d.set(q.resolutionScale, forKey: p + "scale")
        d.set(q.useHEVC, forKey: p + "hevc")
    }
    private static func load(_ slot: MirrorSlot) -> MirrorQuality? {
        let d = UserDefaults.standard, p = "mirrorQ.\(slot.rawValue)."
        guard d.object(forKey: p + "fps") != nil else { return nil }
        return MirrorQuality(
            fps: d.integer(forKey: p + "fps"),
            bitrateBps: d.integer(forKey: p + "bitrate"),
            bitrateAuto: d.bool(forKey: p + "auto"),
            resolutionScale: d.double(forKey: p + "scale"),
            useHEVC: d.bool(forKey: p + "hevc")
        )
    }

    /// Bitrate actually sent: auto (derived from size × fps) or the manual value.
    public func effectiveBitrateBps(width: Int, height: Int, quality q: MirrorQuality) -> Int {
        guard q.bitrateAuto else { return q.bitrateBps }
        let bpp = 0.07   // ~bits/pixel/frame for screen content
        let raw = Double(width) * Double(height) * Double(q.fps) * bpp
        return min(35_000_000, max(6_000_000, Int(raw)))
    }
    public private(set) var decodedFramesPerSecond: Double = 0
    public private(set) var incomingBitrateMbps: Double = 0
    public var remoteAspectRatio: CGFloat {
        max(remoteScreenWidth, 1) / max(remoteScreenHeight, 1)
    }
    public var videoAspectRatio: CGFloat {
        max(videoWidth, 1) / max(videoHeight, 1)
    }

    /// Live decoded-frame subscribers. Each renderer obtains its own stream via
    /// `makeSampleBufferStream()`; frames are fanned out to all of them. A
    /// subscriber that stops consuming (its task is cancelled / its iterator is
    /// dropped) unregisters itself via `onTermination`, so closed renderers
    /// don't kill the feed for renderers opened later.
    private var sampleSubscribers: [UUID: AsyncStream<CMSampleBuffer>.Continuation] = [:]

    /// A fresh AsyncStream of decoded CMSampleBuffers for one renderer.
    /// Consume from `@MainActor` context only. Bounded buffer: an unconsumed
    /// stream only ever holds the newest few frames.
    public func makeSampleBufferStream() -> AsyncStream<CMSampleBuffer> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            // `onTermination` requires a plain `@Sendable` closure; a
            // `@MainActor` closure doesn't convert ("loses global actor"), so
            // hop back to the main actor with a Task. The brief async window
            // before cleanup is harmless: yielding to a finished continuation
            // is a no-op.
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.sampleSubscribers[id] = nil }
            }
            sampleSubscribers[id] = continuation
        }
    }

    /// TLS identity for the mirror listener — injected by `ConnectionService`
    /// (which owns the `TLSIdentityManager`) before `start()` is called.
    /// `nil` at start() is a programmer error: the mirror server won't run.
    public var tlsIdentity: SecIdentity?

    private let server: WebSocketServer
    private var pairingTokenProvider: () -> Data?
    private var decoder: VideoDecoder?
    // Reverse mirror (Mac -> phone)
    private var reversePipeline: ReverseMirrorPipeline?
    private var reverseSendCont: AsyncStream<Data>.Continuation?
    /// The display the active reverse stream is capturing — maps reverse input.
    private var reverseDisplayID: CGDirectDisplayID?
    private var frameCounter = 0
    private var bitrateWindowStartedAt = Date()
    private var bitrateByteCount = 0
    private var fpsWindowStartedAt = Date()
    private var fpsFrameCount = 0

    public init(port: UInt16 = 8767, pairingTokenProvider: @escaping () -> Data? = { nil }) {
        self.pairingTokenProvider = pairingTokenProvider
        self.server = WebSocketServer(port: port)

        // Load per-mode quality, migrating legacy single-setting keys into the
        // forward slot on first run. Built into a local first (self isn't fully
        // initialized until the streams below are set).
        let d = UserDefaults.standard
        let legacyForward = MirrorQuality(
            fps: (d.object(forKey: Self.fpsKey) as? Int) ?? Self.defaultQuality.fps,
            bitrateBps: (d.object(forKey: Self.bitrateKey) as? Int) ?? Self.defaultQuality.bitrateBps,
            bitrateAuto: (d.object(forKey: Self.bitrateAutoKey) as? Bool) ?? Self.defaultQuality.bitrateAuto,
            resolutionScale: (d.object(forKey: Self.resolutionScaleKey) as? Double) ?? Self.defaultQuality.resolutionScale
        )
        var loadedQuality: [Int: MirrorQuality] = [:]
        for slot in MirrorSlot.allCases {
            let fallback = (slot == .forward) ? legacyForward : Self.defaultQuality
            loadedQuality[slot.rawValue] = Self.load(slot) ?? fallback
        }
        self.quality = loadedQuality
    }

    public func setPairingTokenProvider(_ provider: @escaping () -> Data?) {
        self.pairingTokenProvider = provider
    }

    public func start() async throws {
        guard actualPort == nil else { return }
        guard let tlsIdentity else {
            // Programmer error: ConnectionService.provideMirrorTLSIdentity()
            // must run first. Don't start the mirror; main channels still work.
            MirrorDebugLog.write("mirror server NOT started: missing TLS identity")
            return
        }
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
        try await server.start(tlsIdentity: tlsIdentity)
        actualPort = await server.actualPort
        MirrorDebugLog.write("mirror server started on port \(actualPort ?? 0)")
    }

    public func stop() async {
        await server.disconnectAllClients()
        stopReverseMirror()
        actualPort = nil
        isStreaming = false
        decoder?.invalidate()
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

    /// A VideoDecoder wired to the forward (phone -> Mac) sample pipeline. Codec
    /// is selected by which configure(...) the caller invokes.
    private func makeForwardDecoder() -> VideoDecoder {
        VideoDecoder { [weak self] sample in
            let box = UncheckedSampleBuffer(value: sample)
            Task { @MainActor in
                guard let self else { return }
                self.frameCounter += 1
                self.updateDecodedFPS()
                if self.frameCounter <= 10 || self.frameCounter.isMultiple(of: 60) {
                    MirrorDebugLog.write("decoded sample #\(self.frameCounter)")
                }
                for continuation in self.sampleSubscribers.values {
                    continuation.yield(box.value)
                }
            }
        }
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
                let q = quality(.forward)
                let target = nativeStreamSize(for: CGSize(width: remoteScreenWidth, height: remoteScreenHeight), scale: q.resolutionScale)
                targetStreamWidth = Int(target.width)
                targetStreamHeight = Int(target.height)
                let ack = MirrorMessage.helloAck(
                    targetBitrateBps: UInt32(effectiveBitrateBps(width: targetStreamWidth, height: targetStreamHeight, quality: q)),
                    fps: UInt8(q.fps),
                    keyframeIntervalSeconds: 5,
                    targetWidth: UInt32(targetStreamWidth),
                    targetHeight: UInt32(targetStreamHeight),
                    codec: q.useHEVC ? 1 : 0
                )
                bitrateWindowStartedAt = Date()
                bitrateByteCount = 0
                fpsWindowStartedAt = Date()
                fpsFrameCount = 0
                MirrorDebugLog.write("sending HELLO_ACK fps=\(q.fps) size=\(targetStreamWidth)x\(targetStreamHeight) aspect=\(remoteScreenWidth)x\(remoteScreenHeight)")
                Task { try? await server.broadcastBinary(ack.encode()) }
            case let .videoConfig(sps, pps):
                MirrorDebugLog.write("received VIDEO_CONFIG H264 sps=\(sps.count) pps=\(pps.count)")
                let dec = makeForwardDecoder()
                let dims = try dec.configure(sps: sps, pps: pps)
                videoWidth = CGFloat(dims.width)
                videoHeight = CGFloat(dims.height)
                self.decoder?.invalidate()   // drain + free the replaced decoder's VT session
                self.decoder = dec
                self.isStreaming = true

            case let .videoConfigHEVC(vps, sps, pps):
                MirrorDebugLog.write("received VIDEO_CONFIG HEVC vps=\(vps.count) sps=\(sps.count) pps=\(pps.count)")
                let dec = makeForwardDecoder()
                let dims = try dec.configureHEVC(vps: vps, sps: sps, pps: pps)
                videoWidth = CGFloat(dims.width)
                videoHeight = CGFloat(dims.height)
                self.decoder?.invalidate()   // drain + free the replaced decoder's VT session
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

            case let .reverseInput(type, x, y):
                if isReverseStreaming {
                    ReverseInputInjector.injectPointer(type: type, xNorm: x, yNorm: y,
                                                       displayID: reverseDisplayID ?? CGMainDisplayID())
                }

            case let .reverseScroll(dx, dy):
                if isReverseStreaming {
                    ReverseInputInjector.injectScroll(deltaX: dx, deltaY: dy)
                }

            case let .reverseText(text):
                if isReverseStreaming { ReverseInputInjector.injectText(text) }

            case let .reverseKey(code, modifiers):
                if isReverseStreaming { ReverseInputInjector.injectKey(code: code, modifiers: modifiers) }

            case let .reverseHello(token, w, h, mode):
                MirrorDebugLog.write("received REVERSE_HELLO tokenBytes=\(token.count) phone=\(w)x\(h) mode=\(mode)")
                guard let expected = pairingTokenProvider(), token == expected else {
                    MirrorDebugLog.write("REVERSE_HELLO rejected")
                    Task { await server.disconnectAllClients() }
                    return
                }
                startReverseMirror(mode: mode, phoneWidth: Int(w), phoneHeight: Int(h))

            case .status, .helloAck:
                // Status logging is in Plan B; HELLO_ACK is server→client only — ignore if received.
                break
            }
        } catch {
            MirrorDebugLog.write("mirror error: \(error)")
        }
    }

    private func handleDisconnect() {
        stopReverseMirror()
        isStreaming = false
        decoder?.invalidate()
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

    // MARK: - Reverse mirror (Mac -> phone)

    /// Phone asked us to send our screen. Spin up capture+encode and pump the
    /// resulting packets through a single ordered queue so frames stay in order.
    private func startReverseMirror(mode: UInt8 = 0, phoneWidth: Int = 0, phoneHeight: Int = 0) {
        guard reversePipeline == nil else { return }
        let (stream, cont) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        reverseSendCont = cont
        let server = self.server
        Task {
            for await packet in stream {
                try? await server.broadcastBinary(packet)
            }
        }
        let slot: MirrorSlot = (mode == 1) ? .reverseVirtual : .reverseMirror
        let q = quality(slot)
        // UI scale: backing (and thus the "looks like" logical size) scales with
        // resolutionScale. >1 = more desktop space (supersampled, sharp), <1 =
        // bigger UI (slightly upscaled on the phone).
        let virtualSize: (Int, Int)? = (mode == 1 && phoneWidth > 0 && phoneHeight > 0)
            ? (Int(Double(phoneWidth) * q.resolutionScale), Int(Double(phoneHeight) * q.resolutionScale))
            : nil

        // Estimate the encoded size to derive an auto bitrate.
        let (bw, bh): (Int, Int)
        if let (pw, ph) = virtualSize {
            (bw, bh) = Self.fitCap(pw, ph, cap: 3200)
        } else {
            let main = CGMainDisplayID()
            (bw, bh) = Self.fitCap(CGDisplayPixelsWide(main), CGDisplayPixelsHigh(main), cap: 1920)
        }
        let bitrate = effectiveBitrateBps(width: bw, height: bh, quality: q)

        let pipeline = ReverseMirrorPipeline(
            fps: q.fps,
            bitrate: bitrate,
            useHEVC: q.useHEVC,
            virtualSize: virtualSize,
            onPacket: { packet in cont.yield(packet) },
            onLog: { msg in MirrorDebugLog.write(msg) },
            onDisplayID: { [weak self] id in
                Task { @MainActor in self?.reverseDisplayID = id }
            }
        )
        reversePipeline = pipeline
        isReverseStreaming = true
        MirrorDebugLog.write("reverse mirror starting slot=\(slot.rawValue) fps=\(q.fps) bitrate=\(bitrate) hevc=\(q.useHEVC)")
        Task {
            do {
                try await pipeline.start()
            } catch {
                MirrorDebugLog.write("reverse mirror start failed: \(error)")
                await MainActor.run { self.stopReverseMirror() }
            }
        }
    }

    private func stopReverseMirror() {
        guard reversePipeline != nil || reverseSendCont != nil else { return }
        reverseSendCont?.finish()
        reverseSendCont = nil
        let pipeline = reversePipeline
        reversePipeline = nil
        reverseDisplayID = nil
        isReverseStreaming = false
        Task { await pipeline?.stop() }
        MirrorDebugLog.write("reverse mirror stopped")
    }

    private static func fitCap(_ w: Int, _ h: Int, cap: Int) -> (Int, Int) {
        let longEdge = max(w, h)
        let scale = longEdge > cap ? Double(cap) / Double(longEdge) : 1.0
        func even(_ v: Double) -> Int { let r = Int(v.rounded()); return max(2, r - (r % 2)) }
        return (even(Double(w) * scale), even(Double(h) * scale))
    }

    private func nativeStreamSize(for remoteSize: CGSize, scale rawScale: Double) -> CGSize {
        let scale = max(0.25, min(1.0, rawScale))
        let width = max(remoteSize.width * scale, 1)
        let height = max(remoteSize.height * scale, 1)

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
