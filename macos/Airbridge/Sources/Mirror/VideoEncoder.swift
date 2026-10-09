import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

public enum VideoEncoderError: Error, Sendable {
    case sessionCreateFailed(OSStatus)
}

/// Hardware H.264 encoder (VideoToolbox) for the reverse mirror: Mac screen ->
/// phone. Mirror of `VideoDecoder`. Emits raw SPS/PPS (on each keyframe) and
/// Annex-B frame data, matching the wire format the phone decoder expects.
public final class VideoEncoder {
    public struct Config: Sendable {
        public let width: Int32
        public let height: Int32
        public let fps: Int
        public let bitrateBps: Int
        public let keyframeIntervalSeconds: Int
        public let useHEVC: Bool
        public init(width: Int32, height: Int32, fps: Int, bitrateBps: Int, keyframeIntervalSeconds: Int, useHEVC: Bool = false) {
            self.width = width; self.height = height; self.fps = fps
            self.bitrateBps = bitrateBps; self.keyframeIntervalSeconds = keyframeIntervalSeconds
            self.useHEVC = useHEVC
        }
    }

    private var session: VTCompressionSession?
    private let config: Config
    /// Raw parameter sets: [SPS, PPS] for H.264, [VPS, SPS, PPS] for HEVC.
    private let onConfig: @Sendable ([Data]) -> Void
    private let onFrame: @Sendable (Data, UInt64) -> Void   // Annex-B access unit, ptsUs
    /// Called for the first failed frame and then every 300th, with the
    /// VideoToolbox status and the running count of failed frames.
    private let onError: @Sendable (OSStatus, Int) -> Void
    private let errorLock = NSLock()
    private var failedFrames = 0

    public init(config: Config,
                onConfig: @escaping @Sendable ([Data]) -> Void,
                onFrame: @escaping @Sendable (Data, UInt64) -> Void,
                onError: @escaping @Sendable (OSStatus, Int) -> Void = { _, _ in }) throws {
        self.config = config
        self.onConfig = onConfig
        self.onFrame = onFrame
        self.onError = onError
        try createSession()
    }

    deinit {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
    }

    private func createSession() throws {
        var session: VTCompressionSession?
        // Low-latency rate control is a session-creation option, not a property:
        // the hardware encoder then emits every frame as soon as it is coded
        // instead of holding a pipeline of several frames (measured 2026-10-09:
        // up to 13 frames and 380 ms in flight without it).
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
        ]
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: config.width,
            height: config.height,
            codecType: config.useHEVC ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { throw VideoEncoderError.sessionCreateFailed(status) }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) {
            VTSessionSetProperty(session, key: key, value: value)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel,
            config.useHEVC ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: config.bitrateBps))
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: config.fps))
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: config.keyframeIntervalSeconds))
        // Measured 2026-10-09: MaxFrameDelayCount = 0 and PrioritizeEncodingSpeedOverQuality
        // made the hardware HEVC encoder stall ~108 ms two to three times a second, so
        // only the power-efficiency hint stays off.
        set(kVTCompressionPropertyKey_MaximizePowerEfficiency, kCFBooleanFalse)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    /// Encode latency per frame (submit to output), for the diagnostics log.
    private let latencyLock = NSLock()
    private var submitted: [UInt64: UInt64] = [:]   // ptsUs -> uptime ns
    private var maxLatencyMs: Double = 0
    private var maxInFlight = 0
    private var latencySamples = 0
    private var over20 = 0
    private var over40 = 0

    /// Returns the window's encode-latency summary and starts a new window.
    public func latencySummary() -> String {
        latencyLock.lock(); defer { latencyLock.unlock() }
        let s = String(format: "encLatency max=%.0fms >20ms=%d >40ms=%d inFlight max=%d n=%d", maxLatencyMs, over20, over40, maxInFlight, latencySamples)
        maxLatencyMs = 0; maxInFlight = 0; latencySamples = 0; over20 = 0; over40 = 0
        return s
    }

    /// Frames handed to VideoToolbox that have not come back yet. Counted
    /// separately from the latency map: a frame the encoder drops comes back
    /// without a sample buffer, so its timestamp can never be matched.
    public var inFlight: Int {
        latencyLock.lock(); defer { latencyLock.unlock() }
        return inFlightCount
    }
    private var inFlightCount = 0
    /// Dropped frames leave their timestamps behind; forget them after this long.
    private static let submittedTTLNs: UInt64 = 2_000_000_000

    public func encode(pixelBuffer: CVPixelBuffer, ptsUs: UInt64) {
        guard let session else { return }
        latencyLock.lock()
        let now = DispatchTime.now().uptimeNanoseconds
        submitted[ptsUs] = now
        submitted = submitted.filter { now - $0.value < Self.submittedTTLNs }
        inFlightCount += 1
        if inFlightCount > maxInFlight { maxInFlight = inFlightCount }
        latencyLock.unlock()
        let pts = CMTime(value: CMTimeValue(ptsUs), timescale: 1_000_000)
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            self?.handleEncoded(status: status, sampleBuffer: sampleBuffer)
        }
        // Flush this frame out of the encoder before the next one arrives. The
        // hardware encoder otherwise keeps a small pipeline (measured 4-5 frames,
        // 60-220 ms) even with low-latency rate control; a mirror wants each
        // frame on the wire within one frame interval.
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: pts)
    }

    private func handleEncoded(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        latencyLock.lock()
        inFlightCount = max(0, inFlightCount - 1)
        latencyLock.unlock()
        // A frame the rate control could not fit comes back with no error and
        // no sample buffer; it is reported through the same channel so a
        // bitrate too low for the content shows up in the log.
        if status != noErr || sampleBuffer == nil {
            errorLock.lock()
            failedFrames += 1
            let n = failedFrames
            errorLock.unlock()
            if n == 1 || n % 300 == 0 { onError(status, n) }
        }
        guard status == noErr,
              let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let isKeyframe = Self.isKeyframe(sampleBuffer)

        if isKeyframe, let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let sets = Self.parameterSets(fmt, hevc: config.useHEVC)
            if !sets.isEmpty { onConfig(sets) }
        }

        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let s = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard s == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 else { return }

        let avcc = Data(bytes: dataPointer, count: totalLength)
        let annexB = NALUParser.avccToAnnexB(avcc)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000)) : 0
        latencyLock.lock()
        if let t0 = submitted.removeValue(forKey: ptsUs) {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
            if ms > maxLatencyMs { maxLatencyMs = ms }
            if ms > 20 { over20 += 1 }
            if ms > 40 { over40 += 1 }
            latencySamples += 1
        }
        latencyLock.unlock()
        onFrame(annexB, ptsUs)
    }

    private static func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0 else {
            return true   // no attachments -> treat as sync
        }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
        let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
        // NotSync present & true => NOT a keyframe.
        if let raw = CFDictionaryGetValue(dict, key) {
            let notSync = unsafeBitCast(raw, to: CFBoolean.self)
            return !CFBooleanGetValue(notSync)
        }
        return true
    }

    /// Raw parameter sets, no start codes: [SPS, PPS] for H.264, [VPS, SPS, PPS]
    /// for HEVC (the wire order the phone decoder expects).
    private static func parameterSets(_ fmt: CMFormatDescription, hevc: Bool) -> [Data] {
        let expected = hevc ? 3 : 2
        func set(_ index: Int) -> Data? {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            var count = 0
            let status = hevc
                ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fmt, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                : CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            guard status == noErr, let ptr, count >= expected else { return nil }
            return Data(bytes: ptr, count: size)
        }
        var sets: [Data] = []
        for index in 0..<expected {
            guard let data = set(index) else { return [] }
            sets.append(data)
        }
        return sets
    }
}
