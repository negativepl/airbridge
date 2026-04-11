import SwiftUI
import AppKit

@MainActor
final class DropZonePopup {

    static let shared = DropZonePopup()

    private var panel: NSWindow?
    private var isVisible = false
    private var escapeMonitor: Any?
    private var autoHideTimer: Timer?
    private let autoHideDelay: TimeInterval = 5.0

    func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hide()
            }
        }
    }

    func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private init() {}

    var isShowing: Bool { isVisible }

    func toggle(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        if isVisible {
            hide()
        } else {
            show(connectionService: connectionService, fileTransferService: fileTransferService)
        }
    }

    func show(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        if isVisible { return }
        isVisible = true

        let view = DropZoneView(
            connectionService: connectionService,
            fileTransferService: fileTransferService,
            onFileDrop: { [weak self] in
                self?.hide()
            }
        )
        let hostingView = NSHostingView(rootView: view)

        guard let screen = NSScreen.main else { return }
        let (x, y, width, height) = computeLayout(screen: screen)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false

        // Register drag types on the window's content view
        hostingView.registerForDraggedTypes([.fileURL])

        let startY = y + height + 10
        window.setFrame(NSRect(x: x, y: startY, width: width, height: height), display: true)
        window.orderFrontRegardless()
        window.makeKey()
        resetAutoHideTimer()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        self.panel = window

        // Escape key monitor
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        guard isVisible, let panel else { return }

        autoHideTimer?.invalidate()
        autoHideTimer = nil

        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        let frame = panel.frame
        let targetY = frame.origin.y + frame.height + 10

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }, completionHandler: { [weak self] in
            if let monitor = self?.escapeMonitor {
                NSEvent.removeMonitor(monitor)
                self?.escapeMonitor = nil
            }
            panel.orderOut(nil)
            self?.panel = nil
            self?.isVisible = false
        })
    }

    private func computeLayout(screen: NSScreen) -> (x: Double, y: Double, width: Double, height: Double) {
        let defaults = UserDefaults.standard
        let offsetFromTop = defaults.object(forKey: "islandOffsetY") as? Double ?? 0
        let islandWidth = defaults.object(forKey: "islandWidth") as? Double ?? 756
        let height = defaults.object(forKey: "islandHeight") as? Double ?? 130

        let screenFrame = screen.frame
        let x = screenFrame.midX - islandWidth / 2
        let y = screenFrame.maxY - offsetFromTop - height

        return (x, y, islandWidth, height)
    }
}
