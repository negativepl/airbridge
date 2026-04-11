import SwiftUI

struct MainWindow: View {
    @State private var selectedTab: NavigationItem = .home

    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    let fileTransferService: FileTransferService
    let pairingService: PairingService
    let historyService: HistoryService
    let galleryService: GalleryService
    let smsService: SmsService
    let hotkeyService: GlobalHotkeyService

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(NavigationItem.home.title, systemImage: "house.fill", value: .home) {
                ScreenContainer {
                    HomeView(
                        connectionService: connectionService,
                        fileTransferService: fileTransferService,
                        historyService: historyService,
                        pairingService: pairingService
                    )
                }
            }

            Tab(NavigationItem.history.title, systemImage: "clock.arrow.circlepath", value: .history) {
                ScreenContainer(scroll: false) {
                    HistoryView(historyService: historyService)
                }
            }

            Tab(NavigationItem.send.title, systemImage: "paperplane.fill", value: .send) {
                ScreenContainer(scroll: false) {
                    SendView(
                        fileTransferService: fileTransferService,
                        connectionService: connectionService,
                        clipboardService: clipboardService
                    )
                }
            }

            Tab(NavigationItem.gallery.title, systemImage: "photo.on.rectangle", value: .gallery) {
                ScreenContainer(scroll: false) {
                    GalleryView(galleryService: galleryService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.messages.title, systemImage: "message.fill", value: .messages) {
                ScreenContainer(scroll: false) {
                    MessagesView(smsService: smsService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.settings.title, systemImage: "gearshape.fill", value: .settings) {
                ScreenContainer {
                    SettingsView(
                        connectionService: connectionService,
                        pairingService: pairingService,
                        hotkeyService: hotkeyService
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .navigationTitle(selectedTab.title)
    }
}
