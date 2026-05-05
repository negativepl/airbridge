import SwiftUI
import AppKit
import AVFoundation
import CoreMedia

public final class MirrorRendererLayerView: NSView {
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
    }
    public required init?(coder: NSCoder) { fatalError() }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.isReadyForMoreMediaData {
            renderer.enqueue(sampleBuffer)
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
