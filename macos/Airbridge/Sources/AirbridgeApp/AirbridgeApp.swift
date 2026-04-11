import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}


@main
struct AirbridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var connectionService: ConnectionService
    @State private var clipboardService: ClipboardService
    @State private var fileTransferService: FileTransferService
    @State private var pairingService: PairingService
    @State private var historyService: HistoryService
    @State private var galleryService: GalleryService
    @State private var smsService: SmsService
    @State private var hotkeyService: GlobalHotkeyService

    init() {
        UserDefaults.standard.register(defaults: ["playSound": true])

        let connection = ConnectionService()
        let clipboard = ClipboardService()
        let fileTransfer = FileTransferService()
        let pairing = PairingService()
        let history = HistoryService()
        let gallery = GalleryService()
        let sms = SmsService()
        let hotkey = GlobalHotkeyService()

        clipboard.configure(connectionService: connection, historyService: history)
        fileTransfer.configure(connectionService: connection, historyService: history)
        pairing.configure(connectionService: connection)
        gallery.configure(connectionService: connection)
        sms.configure(connectionService: connection)
        hotkey.configure(connectionService: connection, fileTransferService: fileTransfer)
        TransferPopup.shared.configure(connectionService: connection, fileTransferService: fileTransfer)
        connection.registerHandlers(clipboard: clipboard, fileTransfer: fileTransfer, gallery: gallery, sms: sms)

        _connectionService = State(initialValue: connection)
        _clipboardService = State(initialValue: clipboard)
        _fileTransferService = State(initialValue: fileTransfer)
        _pairingService = State(initialValue: pairing)
        _historyService = State(initialValue: history)
        _galleryService = State(initialValue: gallery)
        _smsService = State(initialValue: sms)
        _hotkeyService = State(initialValue: hotkey)

        connection.startServer()
        clipboard.startMonitoring()
        // hotkey.start() is called from body .onAppear to avoid blocking init

        // Set app icon from bundled icns
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some Scene {
        Window("AirBridge", id: "main") {
            Group {
                if onboardingCompleted {
                    MainWindow(
                        connectionService: connectionService,
                        clipboardService: clipboardService,
                        fileTransferService: fileTransferService,
                        pairingService: pairingService,
                        historyService: historyService,
                        galleryService: galleryService,
                        smsService: smsService,
                        hotkeyService: hotkeyService
                    )
                    .onAppear { hotkeyService.start() }
                } else {
                    OnboardingView(
                        pairingService: pairingService,
                        connectionService: connectionService,
                        onComplete: { onboardingCompleted = true }
                    )
                }
            }
            .frame(minWidth: 900, minHeight: 700)
        }
        .defaultSize(width: 1100, height: 850)
        .windowResizability(.contentMinSize)
        .commands {
            // Remove "New Window" and related document commands we don't use.
            CommandGroup(replacing: .newItem) { }

            // Replace Apple menu → About with our custom SwiftUI About window
            // (a Window scene registered below with id "about"). Openable via
            // the openWindow environment action, which must be captured inside
            // a SwiftUI View — hence the AboutMenuButton wrapper.
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }

            // Replace the default Help menu (which shows "Help isn't available
            // for AirBridge") with a single link to the GitHub repo — actual
            // documentation lives there.
            CommandGroup(replacing: .help) {
                Button(L10n.isPL ? "Pomoc AirBridge" : "AirBridge Help") {
                    if let url = URL(string: "https://github.com/negativepl/airbridge") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L10n.isPL ? "Zgłoś problem" : "Report an Issue") {
                    if let url = URL(string: "https://github.com/negativepl/airbridge/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        // Custom About window — minimalist SwiftUI replacement for the stock
        // Aqua-style `orderFrontStandardAboutPanel`. Fixed size, non-resizable,
        // opened from Apple menu or MenuBarExtra.
        Window("AirBridge", id: "about") {
            AboutWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarView(connectionService: connectionService, clipboardService: clipboardService)
        } label: {
            Image(systemName: connectionService.isConnected ? "link.circle.fill" : "link.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Small wrapper to expose `@Environment(\.openWindow)` inside a
/// `CommandGroup`, which otherwise has no SwiftUI environment.
private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L10n.isPL ? "O aplikacji AirBridge" : "About AirBridge") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
