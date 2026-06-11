import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

private enum VideoDecoderDebugLog {
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

public enum VideoDecoderError: Error, Sendable {
    case emptyParameterSet
    case formatDescriptionFailed(OSStatus)
    case sessionCreateFailed(OSStatus)
    case decodeFailed(OSStatus)
}

public final class VideoDecoder: @unchecked Sendable {

    public typealias OnSample = @Sendable (CMSampleBuffer) -> Void

    private let onSample: OnSample
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    public init(onSample: @escaping OnSample) {
        self.onSample = onSample
    }

    @discardableResult
    public func configure(sps: Data, pps: Data) throws -> CMVideoDimensions {
        return try configure(formatDescription: try Self.makeFormatDescription(sps: sps, pps: pps))
    }

    @discardableResult
    public func configureHEVC(vps: Data, sps: Data, pps: Data) throws -> CMVideoDimensions {
        return try configure(formatDescription: try Self.makeFormatDescriptionHEVC(vps: vps, sps: sps, pps: pps))
    }

    @discardableResult
    private func configure(formatDescription fmt: CMVideoFormatDescription) throws -> CMVideoDimensions {
        self.formatDescription = fmt
        // Use PRESENTATION dimensions (clean aperture + pixel aspect), not the
        // raw coded size. H.264 pads to 16px macroblocks, so the coded size can
        // be e.g. 1088×2320 for a 1080×2316 screen — those extra padded pixels
        // made the window slightly wider than the real frame, leaving thin side
        // bars. Presentation dimensions are the true displayed size.
        let presentation = CMVideoFormatDescriptionGetPresentationDimensions(
            fmt, usePixelAspectRatio: true, useCleanAperture: true
        )
        let coded = CMVideoFormatDescriptionGetDimensions(fmt)
        let dims = CMVideoDimensions(
            width: presentation.width > 0 ? Int32(presentation.width.rounded()) : coded.width,
            height: presentation.height > 0 ? Int32(presentation.height.rounded()) : coded.height
        )
        VideoDecoderDebugLog.write("decoder configured presentation=\(dims.width)x\(dims.height) coded=\(coded.width)x\(coded.height)")
        try createSession(formatDescription: fmt)
        return dims
    }

    public func decode(avccFrame: Data, presentationTimestampUs pts: UInt64) throws {
        guard let session, let formatDescription else { return }
        var blockBuffer: CMBlockBuffer?
        var bytes = [UInt8](avccFrame)
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else { throw VideoDecoderError.decodeFailed(status) }
        CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytes.count)

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = bytes.count
        let timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var timings = [timing]
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timings,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else { throw VideoDecoderError.decodeFailed(createStatus) }

        let flags: VTDecodeFrameFlags = ._EnableAsynchronousDecompression
        var infoFlags: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: flags, frameRefcon: nil, infoFlagsOut: &infoFlags)
        if decodeStatus != noErr {
            VideoDecoderDebugLog.write("decode failed status=\(decodeStatus)")
            throw VideoDecoderError.decodeFailed(decodeStatus)
        }
    }

    public static func makeFormatDescription(sps: Data, pps: Data) throws -> CMVideoFormatDescription {
        guard !sps.isEmpty, !pps.isEmpty else { throw VideoDecoderError.emptyParameterSet }
        var formatDesc: CMVideoFormatDescription?
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)
        let parameterSetSizes = [spsBytes.count, ppsBytes.count]
        let status: OSStatus = spsBytes.withUnsafeBufferPointer { spsBuf in
            ppsBytes.withUnsafeBufferPointer { ppsBuf in
                var ptrs: [UnsafePointer<UInt8>] = [spsBuf.baseAddress!, ppsBuf.baseAddress!]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &ptrs,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDesc
                )
            }
        }
        guard status == noErr, let formatDesc else { throw VideoDecoderError.formatDescriptionFailed(status) }
        return formatDesc
    }

    public static func makeFormatDescriptionHEVC(vps: Data, sps: Data, pps: Data) throws -> CMVideoFormatDescription {
        guard !vps.isEmpty, !sps.isEmpty, !pps.isEmpty else { throw VideoDecoderError.emptyParameterSet }
        var formatDesc: CMVideoFormatDescription?
        let vpsBytes = [UInt8](vps)
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)
        let sizes = [vpsBytes.count, spsBytes.count, ppsBytes.count]
        let status: OSStatus = vpsBytes.withUnsafeBufferPointer { vpsBuf in
            spsBytes.withUnsafeBufferPointer { spsBuf in
                ppsBytes.withUnsafeBufferPointer { ppsBuf in
                    var ptrs: [UnsafePointer<UInt8>] = [vpsBuf.baseAddress!, spsBuf.baseAddress!, ppsBuf.baseAddress!]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: &ptrs,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &formatDesc
                    )
                }
            }
        }
        guard status == noErr, let formatDesc else { throw VideoDecoderError.formatDescriptionFailed(status) }
        return formatDesc
    }

    private func createSession(formatDescription: CMVideoFormatDescription) throws {
        // Reconfiguration: tear down the old session first, otherwise the
        // hardware decoder slot it holds leaks until deinit.
        invalidate()

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var session: VTDecompressionSession?
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, _, status, _, imageBuffer, presentationTimeStamp, presentationDuration in
                guard status == noErr,
                      let refCon = decompressionOutputRefCon,
                      let imageBuffer else { return }
                let me = Unmanaged<VideoDecoder>.fromOpaque(refCon).takeUnretainedValue()

                // Build a video format description for the decoded image buffer.
                var imageFormatDesc: CMVideoFormatDescription?
                let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: imageBuffer,
                    formatDescriptionOut: &imageFormatDesc
                )
                guard fmtStatus == noErr, let imageFormatDesc else { return }

                var timing = CMSampleTimingInfo(
                    duration: presentationDuration,
                    presentationTimeStamp: presentationTimeStamp,
                    decodeTimeStamp: .invalid
                )

                var sampleBuffer: CMSampleBuffer?
                let sbStatus = CMSampleBufferCreateForImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: imageBuffer,
                    dataReady: true,
                    makeDataReadyCallback: nil,
                    refcon: nil,
                    formatDescription: imageFormatDesc,
                    sampleTiming: &timing,
                    sampleBufferOut: &sampleBuffer
                )
                guard sbStatus == noErr, let sampleBuffer else { return }
                if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
                    let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                    CFDictionarySetValue(
                        dict,
                        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
                    )
                }

                VideoDecoderDebugLog.write("decoder output sample pts=\(presentationTimeStamp.value)")
                me.onSample(sampleBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else { throw VideoDecoderError.sessionCreateFailed(status) }

        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_MaximizePowerEfficiency, value: kCFBooleanFalse)
        self.session = session
    }

    /// Tears down the decompression session. Blocks until all in-flight
    /// asynchronous frames have been emitted BEFORE invalidating — the output
    /// callback holds `self` via an unretained refCon, so a callback arriving
    /// after the decoder is freed would be a use-after-free. After this
    /// returns no further output callbacks can fire.
    ///
    /// Call explicitly when replacing/discarding a decoder; `deinit` also
    /// calls it as a safety net.
    public func invalidate() {
        guard let session else { return }
        self.session = nil
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        VTDecompressionSessionInvalidate(session)
    }

    deinit {
        invalidate()
    }
}
