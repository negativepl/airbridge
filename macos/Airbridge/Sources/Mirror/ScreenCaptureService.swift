import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

public enum ScreenCaptureError: Error, Sendable {
    case noDisplay
}

/// Captures the Mac's main display via ScreenCaptureKit and hands raw
/// CVPixelBuffers to a callback (for the reverse-mirror encoder). Requires the
/// Screen Recording permission. Mirror of Android's MediaProjection capture.
public final class ScreenCaptureService: NSObject, SCStreamOutput {
    /// Cap the long edge so we don't stream a full 3.5K retina panel to a phone.
    public static let defaultMaxLongEdge = 1920

    private var stream: SCStream?
    private let onConfigured: @Sendable (Int, Int) -> Void          // output width, height (px)
    private let onFrame: @Sendable (CVPixelBuffer, UInt64) -> Void   // pixelBuffer, ptsUs
    private let queue = DispatchQueue(label: "com.airbridge.screencapture")
    private let targetDisplayID: CGDirectDisplayID?
    private let capLongEdge: Int?
    private let forcedOutputSize: (Int, Int)?

    /// - targetDisplayID: capture this specific display (nil = main display).
    /// - capLongEdge: downscale so the long edge fits this (nil = native).
    /// - forcedOutputSize: capture at exactly this pixel size, ignoring the
    ///   display's point size. Used for a HiDPI virtual display so we grab full
    ///   backing pixels (sharp) rather than the halved logical size.
    public init(targetDisplayID: CGDirectDisplayID? = nil,
                capLongEdge: Int? = ScreenCaptureService.defaultMaxLongEdge,
                forcedOutputSize: (Int, Int)? = nil,
                onConfigured: @escaping @Sendable (Int, Int) -> Void,
                onFrame: @escaping @Sendable (CVPixelBuffer, UInt64) -> Void) {
        self.targetDisplayID = targetDisplayID
        self.capLongEdge = capLongEdge
        self.forcedOutputSize = forcedOutputSize
        self.onConfigured = onConfigured
        self.onFrame = onFrame
        super.init()
    }

    public func start() async throws {
        // A freshly-created virtual display can take a moment to register.
        var display: SCDisplay?
        for attempt in 0..<10 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let target = targetDisplayID {
                display = content.displays.first(where: { $0.displayID == target })
            } else {
                display = content.displays.first
            }
            if display != nil { break }
            if attempt < 9 { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        guard let display else { throw ScreenCaptureError.noDisplay }

        // display.width/height are in points; scale to a sensible even pixel size.
        let (outW, outH) = forcedOutputSize ?? Self.outputSize(width: display.width, height: display.height, cap: capLongEdge)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = outW
        config.height = outH
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)   // up to 60 fps
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        config.queueDepth = 5
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        onConfigured(outW, outH)
    }

    public func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    private static func outputSize(width: Int, height: Int, cap: Int?) -> (Int, Int) {
        func even(_ v: Double) -> Int { let r = Int(v.rounded()); return r - (r % 2) }
        let longEdge = max(width, height)
        let scale = (cap != nil && longEdge > cap!) ? Double(cap!) / Double(longEdge) : 1.0
        return (max(2, even(Double(width) * scale)), max(2, even(Double(height) * scale)))
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }

        // Only forward frames that are complete (skip idle/blank status frames).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let statusRaw = info[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000)) : 0
        onFrame(pixelBuffer, ptsUs)
    }
}
