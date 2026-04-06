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

    init() {
        UserDefaults.standard.register(defaults: ["playSound": true])

        let connection = ConnectionService()
        let clipboard = ClipboardService()
        let fileTransfer = FileTransferService()
        let pairing = PairingService()
        let history = HistoryService()
        let gallery = GalleryService()
        let sms = SmsService()

        clipboard.configure(connectionService: connection, historyService: history)
        fileTransfer.configure(connectionService: connection, historyService: history)
        pairing.configure(connectionService: connection)
        gallery.configure(connectionService: connection)
        sms.configure(connectionService: connection)
        connection.registerHandlers(clipboard: clipboard, fileTransfer: fileTransfer, gallery: gallery, sms: sms)

        _connectionService = State(initialValue: connection)
        _clipboardService = State(initialValue: clipboard)
        _fileTransferService = State(initialValue: fileTransfer)
        _pairingService = State(initialValue: pairing)
        _historyService = State(initialValue: history)
        _galleryService = State(initialValue: gallery)
        _smsService = State(initialValue: sms)

        connection.startServer()
        clipboard.startMonitoring()

        // Set app icon from bundled icns
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        Window("Airbridge", id: "main") {
            MainWindow(
                connectionService: connectionService,
                clipboardService: clipboardService,
                fileTransferService: fileTransferService,
                pairingService: pairingService,
                historyService: historyService,
                galleryService: galleryService,
                smsService: smsService
            )
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
