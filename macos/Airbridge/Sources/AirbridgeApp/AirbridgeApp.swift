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
        hotkey.start()

        // Set app icon from bundled icns
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    @AppStorage("onboardingCompleted") private var onboardingCompleted = false

    var body: some Scene {
        Window("Airbridge", id: "main") {
            if onboardingCompleted {
                MainWindow(
                    connectionService: connectionService,
                    clipboardService: clipboardService,
                    fileTransferService: fileTransferService,
                    pairingService: pairingService,
                    historyService: historyService,
                    galleryService: galleryService,
                    smsService: smsService
                )
            } else {
                OnboardingView(
                    pairingService: pairingService,
                    connectionService: connectionService,
                    onComplete: { onboardingCompleted = true }
                )
            }
        }
        .defaultSize(width: 1100, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarView(connectionService: connectionService, clipboardService: clipboardService)
        } label: {
            Image(systemName: connectionService.isConnected ? "link.circle.fill" : "link.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
