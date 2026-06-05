import SwiftUI
import AppKit
import AVFoundation
import CoreMedia

private enum MirrorRendererDebugLog {
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

public final class MirrorRendererLayerView: NSView {
    private var enqueuedCount = 0
    private var droppedCount = 0

    public override func makeBackingLayer() -> CALayer {
        return AVSampleBufferDisplayLayer()
    }
    public override var wantsUpdateLayer: Bool { true }

    public var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = false
    }
    public required init?(coder: NSCoder) { fatalError() }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            MirrorRendererDebugLog.write("display layer failed: \(String(describing: displayLayer.error))")
            displayLayer.flushAndRemoveImage()
        }
        if displayLayer.isReadyForMoreMediaData {
            enqueuedCount += 1
            if enqueuedCount <= 10 || enqueuedCount.isMultiple(of: 60) {
                MirrorRendererDebugLog.write("renderer enqueued sample #\(enqueuedCount)")
            }
            displayLayer.enqueue(sampleBuffer)
        } else {
            droppedCount += 1
            if droppedCount <= 10 || droppedCount.isMultiple(of: 30) {
                MirrorRendererDebugLog.write("display layer not ready for media data, dropping sample #\(droppedCount)")
            }
            if droppedCount.isMultiple(of: 5) {
                displayLayer.flush()
            }
        }
    }
}

public struct MirrorRendererView: NSViewRepresentable {
    public final class Coordinator {
        weak var view: MirrorRendererLayerView?
    }

    private let stream: AsyncStream<CMSampleBuffer>

    public init(stream: AsyncStream<CMSampleBuffer>) {
        self.stream = stream
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> MirrorRendererLayerView {
        let view = MirrorRendererLayerView(frame: .zero)
        context.coordinator.view = view
        Task { @MainActor in
            for await sample in stream {
                context.coordinator.view?.enqueue(sample)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: MirrorRendererLayerView, context: Context) {}
}
