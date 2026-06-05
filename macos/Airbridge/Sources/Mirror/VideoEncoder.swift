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

    public init(config: Config,
                onConfig: @escaping @Sendable ([Data]) -> Void,
                onFrame: @escaping @Sendable (Data, UInt64) -> Void) throws {
        self.config = config
        self.onConfig = onConfig
        self.onFrame = onFrame
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
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: config.width,
            height: config.height,
            codecType: config.useHEVC ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
            encoderSpecification: nil,
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
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    public func encode(pixelBuffer: CVPixelBuffer, ptsUs: UInt64) {
        guard let session else { return }
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
    }

    private func handleEncoded(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
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
