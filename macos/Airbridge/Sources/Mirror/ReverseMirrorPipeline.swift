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
    /// The capture never exceeds the virtual display's 60 Hz, and asking the
    /// encoder for more makes H.264 reject large frames (level limits), so
    /// the requested rate is capped here.
    private var effectiveFps: Int { min(fps, 60) }
    private let onPacket: @Sendable (Data) -> Void
    private let onLog: @Sendable (String) -> Void
    /// The CGDirectDisplayID being captured — for mapping reverse-control input.
    private let onDisplayID: @Sendable (UInt32) -> Void

    private var capture: ScreenCaptureService?
    private var encoder: VideoEncoder?
    private var virtualDisplay: ABVirtualDisplay?
    private let lock = NSLock()
    private let frameCount = Counter()
    let captureGaps = GapStats()
    let encodeGaps = GapStats()
    private let encodedCount = Counter()
    private let skippedCount = Counter()
    /// Capture frames are dropped while this many are still in the encoder.
    private static let maxFramesInFlight = 2
    /// Longest edge of the encoded frame. The hardware encoder needs about
    /// 14 ms per 2184x1968 frame and 24 ms per 3056x2754 frame (HEVC and
    /// H.264 alike, measured 2026-10-09), so anything larger cannot reach
    /// 60 fps; a bigger virtual display is captured scaled down to this.
    private static let encodeLongEdgeCap = 2200
    /// Shortest backing edge of the virtual display. macOS marks a 2x mode
    /// below 600 pt on its short edge as unusable for the desktop and keeps
    /// the stock 800x600 mode instead, so the folded Fold's 21:9 cover panel
    /// (1008x432 pt) arrived as a letterboxed 4:3 desktop. Measured 2026-10-10:
    /// 1400x600 and 600x1400 pt are accepted, 1200x514 pt is not.
    private static let minBackingShortEdge = 1200

    public init(fps: Int, bitrate: Int, useHEVC: Bool = false,
                virtualSize: (Int, Int)? = nil,
                onPacket: @escaping @Sendable (Data) -> Void,
                onLog: @escaping @Sendable (String) -> Void = { _ in },
                onDisplayID: @escaping @Sendable (UInt32) -> Void = { _ in }) {
        self.fps = fps
        self.bitrate = bitrate
        self.useHEVC = useHEVC
        self.virtualSize = virtualSize
        self.onPacket = onPacket
        self.onLog = onLog
        self.onDisplayID = onDisplayID
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
            // (comfortable UI), exactly like a Retina display. A panel too small
            // for macOS's minimum gets a larger display of the same aspect,
            // captured down to the phone's size.
            let (bw, bh) = Self.enlarge(dw, dh, minShortEdge: Self.minBackingShortEdge)
            let vd = ABVirtualDisplay(width: UInt32(bw), height: UInt32(bh), hiDPI: true, name: "AirBridge Phone")
            guard let vd, vd.displayID != 0 else {
                onLog("virtual display FAILED: \(vd?.failureReason ?? "nil")")
                throw ScreenCaptureError.noDisplay
            }
            virtualDisplay = vd
            targetDisplayID = vd.displayID
            capLongEdge = nil
            forcedOutputSize = Self.fit(dw, dh, cap: Self.encodeLongEdgeCap)   // backing pixels (not halved points), scaled down only above the encoder's limit
            onLog("virtual display created id=\(vd.displayID) \(bw)x\(bh) for \(dw)x\(dh) (HiDPI) mode=\(vd.selectedMode ?? "?")")
            onDisplayID(vd.displayID)
        } else {
            onDisplayID(CGMainDisplayID())
        }

        let capture = ScreenCaptureService(
            fps: effectiveFps,
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
                            fps: self.effectiveFps, bitrateBps: self.bitrate, keyframeIntervalSeconds: 5,
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
                            self.encodeGaps.record()
                            if n == 1 || n % 60 == 0 { self.onLog("reverse encoded frame #\(n) bytes=\(annexB.count) \(self.encodeGaps.flush()) \(self.currentEncoder()?.latencySummary() ?? "")") }
                            self.onPacket(MirrorMessage.videoFrame(presentationTimestampUs: pts, naluBytes: annexB).encode())
                        },
                        onError: { status, failed in
                            self.onLog(status == noErr ? "reverse encoder dropped frame (\(failed) total, bitrate too low for the content)" : "reverse encode error \(status) (\(failed) frames failed)")
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
                self.captureGaps.record()
                // The luma probe walks the whole frame on the capture thread, so it
                // runs only for the first frames ("is the capture black?"); the
                // periodic line reports cadence only.
                if n <= 3 {
                    let (luma, w, h) = Self.avgLuma(pixelBuffer)
                    self.onLog("reverse captured frame #\(n) \(w)x\(h) avgLuma=\(luma)")
                } else if n % 60 == 0 {
                    self.onLog("reverse captured frame #\(n) \(self.captureGaps.flush())")
                }
                guard let encoder = self.currentEncoder() else { return }
                // An encoder that cannot keep up must drop frames, not queue
                // them: queued frames only add latency (377 frames in flight
                // measured with H.264 at 3056x2754 before this guard).
                if encoder.inFlight >= Self.maxFramesInFlight {
                    let skipped = self.skippedCount.increment()
                    if skipped == 1 || skipped % 60 == 0 { self.onLog("reverse capture skipped frame (\(skipped) total, encoder busy)") }
                    return
                }
                encoder.encode(pixelBuffer: pixelBuffer, ptsUs: pts)
            }
        )
        self.capture = capture
        try await capture.start()
    }

    public func stop() async {
        // Tear down the virtual display FIRST and explicitly. If capture.stop()
        // below ever hangs, an orphaned display must not survive — it can become
        // the main screen and steal the user's windows.
        virtualDisplay?.invalidate()
        virtualDisplay = nil
        await capture?.stop()
        capture = nil
        clearEncoder()
    }

    /// Fit (w,h) so the long edge is at most `cap`, keeping aspect, even pixels.
    /// Scales (w, h) up, keeping its aspect, until the short edge reaches
    /// `minShortEdge`; even dimensions, unchanged when already large enough.
    static func enlarge(_ w: Int, _ h: Int, minShortEdge: Int) -> (Int, Int) {
        let shortEdge = min(w, h)
        guard shortEdge > 0, shortEdge < minShortEdge else { return (w, h) }
        let scale = Double(minShortEdge) / Double(shortEdge)
        func even(_ v: Double) -> Int { let r = Int(v.rounded()); return r + (r % 2) }
        return (even(Double(w) * scale), even(Double(h) * scale))
    }

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

/// Inter-arrival statistics for one stage of the pipeline, reported per log
/// window: the largest gap and how many gaps exceeded 50 ms (a stall at 60 fps).
public final class GapStats: @unchecked Sendable {
    private let lock = NSLock()
    private var last: UInt64 = 0
    private var maxGapMs: Double = 0
    private var stalls = 0
    private var count = 0

    public init() {}

    public func record() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        if last != 0 {
            let gap = Double(now - last) / 1_000_000
            count += 1
            if gap > maxGapMs { maxGapMs = gap }
            if gap > 50 { stalls += 1 }
        }
        last = now
    }

    /// Returns the window's summary and starts a new window.
    public func flush() -> String {
        lock.lock(); defer { lock.unlock() }
        let s = String(format: "gaps=%d maxGap=%.0fms stalls>50ms=%d", count, maxGapMs, stalls)
        count = 0; maxGapMs = 0; stalls = 0
        return s
    }
}
