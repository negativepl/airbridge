import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import CoreImage

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
    private var droppedCount = 0

    /// Foreground: the actual mirror, aspect-fit (letterboxed).
    private let displayLayer = AVSampleBufferDisplayLayer()
    /// Background "ambient/cinema" fill: same frames scaled to fill + heavily
    /// blurred, so the letterbox bars glow with the screen's colours instead
    /// of being flat black (à la YouTube ambient mode).
    private let ambientLayer = AVSampleBufferDisplayLayer()

    public override func makeBackingLayer() -> CALayer { CALayer() }
    public override var wantsUpdateLayer: Bool { true }

    private let ambientEnabled: Bool

    public init(frame frameRect: NSRect, ambient: Bool) {
        self.ambientEnabled = ambient
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        if ambient {
            ambientLayer.videoGravity = .resizeAspectFill
            ambientLayer.preventsDisplaySleepDuringVideoPlayback = false
            ambientLayer.opacity = 0.55
            if let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 60]) {
                ambientLayer.filters = [blur]
            }
            layer?.addSublayer(ambientLayer)
        }

        // Always aspect-fit (never crop). In the tab the ambient layer fills
        // the letterbox bars; the pop-out window aspect-locks to the video so
        // there are no bars to fill.
        displayLayer.videoGravity = .resizeAspect
        displayLayer.preventsDisplaySleepDuringVideoPlayback = false
        layer?.addSublayer(displayLayer)
    }
    public required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if ambientEnabled {
            // Oversize the ambient layer so its Gaussian blur never reveals
            // soft transparent edges inside the view.
            let inset = -max(bounds.width, bounds.height) * 0.1
            ambientLayer.frame = bounds.insetBy(dx: inset, dy: inset)
        }
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let layers = ambientEnabled ? [ambientLayer, displayLayer] : [displayLayer]
        for layer in layers {
            if layer.status == .failed {
                layer.flushAndRemoveImage()
            }
            if layer.isReadyForMoreMediaData {
                layer.enqueue(sampleBuffer)
            } else if layer === displayLayer {
                droppedCount += 1
                if droppedCount.isMultiple(of: 5) { layer.flush() }
            }
        }
    }
}

public struct MirrorRendererView: NSViewRepresentable {
    public final class Coordinator {
        weak var view: MirrorRendererLayerView?
        var consumeTask: Task<Void, Never>?
    }

    private let makeStream: @MainActor () -> AsyncStream<CMSampleBuffer>
    private let ambient: Bool

    /// `streamFactory` is invoked once per created NSView (in `makeNSView`),
    /// not per SwiftUI body evaluation, so each renderer holds exactly one
    /// live subscription that is torn down in `dismantleNSView`.
    ///
    /// `ambient: true` fills letterbox bars with a blurred glow of the screen
    /// (for the tab, where the area is wider than the phone). Pass `false` for
    /// the pop-out window, which resizes to the phone aspect — pure video.
    public init(streamFactory: @escaping @MainActor () -> AsyncStream<CMSampleBuffer>, ambient: Bool = true) {
        self.makeStream = streamFactory
        self.ambient = ambient
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> MirrorRendererLayerView {
        let view = MirrorRendererLayerView(frame: .zero, ambient: ambient)
        let coordinator = context.coordinator
        coordinator.view = view
        let stream = makeStream()
        coordinator.consumeTask = Task { @MainActor in
            for await sample in stream {
                coordinator.view?.enqueue(sample)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: MirrorRendererLayerView, context: Context) {}

    public static func dismantleNSView(_ nsView: MirrorRendererLayerView, coordinator: Coordinator) {
        // Without this the consume task outlives the view; reopening the
        // mirror window would leave two tasks competing for frames.
        coordinator.consumeTask?.cancel()
        coordinator.consumeTask = nil
        coordinator.view = nil
    }
}
