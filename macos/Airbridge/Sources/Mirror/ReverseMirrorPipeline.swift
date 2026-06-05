import Foundation
import CoreVideo
import CoreGraphics
import CVirtualDisplay

/// Reverse mirror (Mac -> phone): captures the Mac screen, encodes it, and
/// hands ready-to-send `MirrorMessage` packets (videoConfig / videoFrame) to
/// `onPacket` in capture order. Kept off the main actor; thread safety for the
/// encoder handoff is via the lock.
public final class ReverseMirrorPipeline: @unchecked Sendable {
    private let fps: Int
    private let bitrate: Int
    private let useHEVC: Bool
    /// If set, create a virtual display of (roughly) this pixel size and capture
    /// it — the phone becomes a perfectly-shaped second monitor. nil = mirror the
    /// Mac's main display (letterboxed on the phone).
    private let virtualSize: (Int, Int)?
    private let onPacket: @Sendable (Data) -> Void
    private let onLog: @Sendable (String) -> Void

    private var capture: ScreenCaptureService?
    private var encoder: VideoEncoder?
    private var virtualDisplay: ABVirtualDisplay?
    private let lock = NSLock()
    private let frameCount = Counter()
    private let encodedCount = Counter()

    public init(fps: Int, bitrate: Int, useHEVC: Bool = false,
                virtualSize: (Int, Int)? = nil,
                onPacket: @escaping @Sendable (Data) -> Void,
                onLog: @escaping @Sendable (String) -> Void = { _ in }) {
        self.fps = fps
        self.bitrate = bitrate
        self.useHEVC = useHEVC
        self.virtualSize = virtualSize
        self.onPacket = onPacket
        self.onLog = onLog
    }

    public func start() async throws {
        var targetDisplayID: CGDirectDisplayID? = nil
        var capLongEdge: Int? = ScreenCaptureService.defaultMaxLongEdge
        var forcedOutputSize: (Int, Int)? = nil

        if let (pw, ph) = virtualSize {
            // Backing size for the virtual display (already scaled by the UI-scale
            // setting), capped for very large panels.
            let (dw, dh) = Self.fit(pw, ph, cap: 3200)
            // HiDPI: backing = native pixels (sharp), logical "looks like" = half
            // (comfortable UI), exactly like a Retina display.
            let vd = ABVirtualDisplay(width: UInt32(dw), height: UInt32(dh), hiDPI: true, name: "AirBridge Phone")
            guard let vd, vd.displayID != 0 else {
                onLog("virtual display FAILED: \(vd?.failureReason ?? "nil")")
                throw ScreenCaptureError.noDisplay
            }
            virtualDisplay = vd
            targetDisplayID = vd.displayID
            capLongEdge = nil
            forcedOutputSize = (dw, dh)   // capture full backing pixels, not halved points
            onLog("virtual display created id=\(vd.displayID) \(dw)x\(dh) (HiDPI) mode=\(vd.selectedMode ?? "?")")
        }

        let capture = ScreenCaptureService(
            targetDisplayID: targetDisplayID,
            capLongEdge: capLongEdge,
            forcedOutputSize: forcedOutputSize,
            onConfigured: { [weak self] w, h in
                guard let self else { return }
                self.onLog("reverse capture configured \(w)x\(h)")
                do {
                    let enc = try VideoEncoder(
                        config: VideoEncoder.Config(
                            width: Int32(w), height: Int32(h),
                            fps: self.fps, bitrateBps: self.bitrate, keyframeIntervalSeconds: 5,
                            useHEVC: self.useHEVC
                        ),
                        onConfig: { sets in
                            if sets.count == 3 {
                                self.onLog("reverse videoConfig HEVC vps=\(sets[0].count) sps=\(sets[1].count) pps=\(sets[2].count)")
                                self.onPacket(MirrorMessage.videoConfigHEVC(vps: sets[0], sps: sets[1], pps: sets[2]).encode())
                            } else if sets.count == 2 {
                                self.onLog("reverse videoConfig H264 sps=\(sets[0].count) pps=\(sets[1].count)")
                                self.onPacket(MirrorMessage.videoConfig(sps: sets[0], pps: sets[1]).encode())
                            }
                        },
                        onFrame: { annexB, pts in
                            let n = self.encodedCount.increment()
                            if n == 1 || n % 60 == 0 { self.onLog("reverse encoded frame #\(n) bytes=\(annexB.count)") }
                            self.onPacket(MirrorMessage.videoFrame(presentationTimestampUs: pts, naluBytes: annexB).encode())
                        }
                    )
                    self.setEncoder(enc)
                    self.onLog("reverse encoder created")
                } catch {
                    self.onLog("reverse encoder init FAILED: \(error)")
                }
            },
            onFrame: { [weak self] pixelBuffer, pts in
                guard let self else { return }
                let n = self.frameCount.increment()
                if n <= 3 || n % 60 == 0 {
                    let (luma, w, h) = Self.avgLuma(pixelBuffer)
                    self.onLog("reverse captured frame #\(n) \(w)x\(h) avgLuma=\(luma)")
                }
                self.currentEncoder()?.encode(pixelBuffer: pixelBuffer, ptsUs: pts)
            }
        )
        self.capture = capture
        try await capture.start()
    }

    public func stop() async {
        await capture?.stop()
        capture = nil
        clearEncoder()
        virtualDisplay = nil   // releasing removes the virtual display
    }

    /// Fit (w,h) so the long edge is at most `cap`, keeping aspect, even pixels.
    static func fit(_ w: Int, _ h: Int, cap: Int) -> (Int, Int) {
        let longEdge = max(w, h)
        let scale = longEdge > cap ? Double(cap) / Double(longEdge) : 1.0
        func even(_ v: Double) -> Int { let r = Int(v.rounded()); return max(2, r - (r % 2)) }
        return (even(Double(w) * scale), even(Double(h) * scale))
    }

    private func setEncoder(_ enc: VideoEncoder?) {
        lock.lock(); encoder = enc; lock.unlock()
    }

    private func currentEncoder() -> VideoEncoder? {
        lock.lock(); defer { lock.unlock() }; return encoder
    }

    private func clearEncoder() {
        lock.lock(); encoder = nil; lock.unlock()
    }
}

extension ReverseMirrorPipeline {
    /// Average luma over a sparse sample of the Y plane — diagnostic for "is the
    /// capture actually black?". Returns (avgLuma 0-255, width, height).
    static func avgLuma(_ pb: CVPixelBuffer) -> (Int, Int, Int) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return (-1, w, h) }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        let stepY = max(1, h / 32), stepX = max(1, w / 32)
        var y = 0
        while y < h {
            var x = 0
            while x < w { sum += Int(ptr[y * rowBytes + x]); count += 1; x += stepX }
            y += stepY
        }
        return (count > 0 ? sum / count : -1, w, h)
    }
}

/// Tiny thread-safe counter for diagnostics.
private final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
