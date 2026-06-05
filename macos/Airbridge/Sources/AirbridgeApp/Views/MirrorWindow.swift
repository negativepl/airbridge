import SwiftUI
import Mirror
import AppKit

struct MirrorWindow: View {
    private static let minShortEdge: CGFloat = 420

    let mirrorService: MirrorService
    @State private var window: NSWindow?
    @State private var showsInfo = false
    @State private var titlebarInset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                MirrorRendererView(stream: mirrorService.sampleBufferStream)
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

                headerIcon(systemName: "info.circle") {
                    showsInfo.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .padding(.top, titlebarInset + 8)
                .padding(.trailing, 14)

                if showsInfo {
                    MirrorInfoPanel(mirrorService: mirrorService)
                        .padding(.top, titlebarInset + 54)
                        .padding(.trailing, 14)
                }
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
    }

    private func headerIcon(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.ab(.subheadline, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
        let y = 1 - ((location.y - origin.y) / fitted.height)
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
        window.showsResizeIndicator = true
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

private struct MirrorInfoPanel: View {
    let mirrorService: MirrorService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mirror Info")
                .font(.headline)
            infoRow("Telefon", "\(Int(mirrorService.remoteScreenWidth)) × \(Int(mirrorService.remoteScreenHeight))")
            infoRow("Stream", "\(mirrorService.targetStreamWidth) × \(mirrorService.targetStreamHeight)")
            infoRow("FPS", String(format: "%.1f", mirrorService.decodedFramesPerSecond))
            infoRow("Bitrate", String(format: "%.2f Mbps", mirrorService.incomingBitrateMbps))
            infoRow("Port", "\(mirrorService.actualPort ?? 0)")
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
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
