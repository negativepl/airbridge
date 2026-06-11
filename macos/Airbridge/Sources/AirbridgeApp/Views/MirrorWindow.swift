import SwiftUI
import Mirror
import AppKit

struct MirrorWindow: View {
    private static let minShortEdge: CGFloat = 420

    let mirrorService: MirrorService
    @State private var window: NSWindow?
    @State private var titlebarInset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                MirrorRendererView(streamFactory: mirrorService.makeSampleBufferStream, ambient: true)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                guard let point = normalizedPoint(
                                    location: value.location,
                                    in: proxy.size,
                                    aspectRatio: mirrorService.videoAspectRatio
                                ) else { return }
                                mirrorService.sendTap(xNorm: point.x, yNorm: point.y)
                            }
                    )
            }
        }
        .background(WindowAccessor { nsWindow in
            configureWindow(nsWindow)
            updateTitlebarInset(nsWindow)
            if window !== nsWindow {
                window = nsWindow
                resizeWindowIfNeeded(nsWindow)
            }
        })
        .onChange(of: mirrorService.videoWidth) { _, _ in
            if let window { resizeWindowIfNeeded(window) }
        }
        .onChange(of: mirrorService.videoHeight) { _, _ in
            if let window { resizeWindowIfNeeded(window) }
        }
        .onExitCommand {
            Task { await mirrorService.stop() }
        }
        .onAppear {
            mirrorService.presentedInWindow = true
            if let window { resizeWindowIfNeeded(window) }
        }
        .onDisappear { mirrorService.presentedInWindow = false }
    }

    private func normalizedPoint(location: CGPoint, in size: CGSize, aspectRatio: CGFloat) -> CGPoint? {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return nil }

        let fitted: CGSize
        if size.width / size.height > aspectRatio {
            let height = size.height
            fitted = CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = size.width
            fitted = CGSize(width: width, height: width / aspectRatio)
        }

        let origin = CGPoint(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2
        )

        guard location.x >= origin.x,
              location.y >= origin.y,
              location.x <= origin.x + fitted.width,
              location.y <= origin.y + fitted.height else {
            return nil
        }

        let x = (location.x - origin.x) / fitted.width
        // Top-down, matching Android screen coords (0 = top). No flip.
        let y = (location.y - origin.y) / fitted.height
        return CGPoint(x: x, y: y)
    }

    private func resizeWindowIfNeeded(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 80, dy: 80)
        let aspect = max(mirrorService.videoAspectRatio, 0.2)
        let minSize = minimumContentSize(for: aspect)
        let nativeAspectSize = NSSize(
            width: max(mirrorService.videoWidth, 1),
            height: max(mirrorService.videoHeight, 1)
        )

        var targetWidth = min(visible.width * 0.45, 620)
        var targetHeight = targetWidth / aspect

        if targetHeight < minSize.height {
            targetHeight = minSize.height
            targetWidth = targetHeight * aspect
        }

        if targetWidth < minSize.width {
            targetWidth = minSize.width
            targetHeight = targetWidth / aspect
        }

        if targetHeight > visible.height * 0.9 {
            targetHeight = visible.height * 0.9
            targetWidth = targetHeight * aspect
        }

        if targetWidth > visible.width * 0.8 {
            targetWidth = visible.width * 0.8
            targetHeight = targetWidth / aspect
        }

        let newSize = NSSize(width: targetWidth.rounded(), height: targetHeight.rounded())
        if abs(window.frame.size.width - newSize.width) < 1,
           abs(window.frame.size.height - newSize.height) < 1 {
            return
        }

        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: newSize))
        frame.origin = CGPoint(
            x: window.frame.midX - frame.size.width / 2,
            y: window.frame.midY - frame.size.height / 2
        )
        window.setFrame(frame, display: true, animate: true)
        window.contentAspectRatio = nativeAspectSize
        window.contentMinSize = minSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minSize)).size
        updateTitlebarInset(window)
    }

    private func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }

    private func updateTitlebarInset(_ window: NSWindow) {
        let inset = max(0, window.frame.height - window.contentLayoutRect.height)
        if abs(titlebarInset - inset) > 0.5 {
            titlebarInset = inset
        }
    }

    private func minimumContentSize(for aspect: CGFloat) -> NSSize {
        if aspect >= 1 {
            return NSSize(
                width: (Self.minShortEdge * aspect).rounded(.up),
                height: Self.minShortEdge
            )
        } else {
            return NSSize(
                width: Self.minShortEdge,
                height: (Self.minShortEdge / aspect).rounded(.up)
            )
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
