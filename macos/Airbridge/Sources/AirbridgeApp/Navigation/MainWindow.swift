import SwiftUI
import Mirror

struct MainWindow: View {
    @State private var selectedTab: NavigationItem = .home

    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    let fileTransferService: FileTransferService
    let pairingService: PairingService
    let galleryService: GalleryService
    let smsService: SmsService
    let filesBrowserService: FilesBrowserService
    let hotkeyService: GlobalHotkeyService
    let mirrorService: MirrorService

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(NavigationItem.home.title, systemImage: "house.fill", value: .home) {
                ScreenContainer {
                    HomeView(
                        connectionService: connectionService,
                        fileTransferService: fileTransferService,
                        pairingService: pairingService
                    )
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

            Tab(NavigationItem.files.title, systemImage: "folder.fill", value: .files) {
                ScreenContainer(scroll: false) {
                    FilesBrowserView(filesBrowserService: filesBrowserService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.messages.title, systemImage: "message.fill", value: .messages) {
                ScreenContainer(scroll: false) {
                    MessagesView(smsService: smsService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.mirror.title, systemImage: "iphone.gen3.radiowaves.left.and.right", value: .mirror) {
                ScreenContainer(scroll: false) {
                    MirrorTabView(mirrorService: mirrorService, connectionService: connectionService)
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
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        .navigationTitle(selectedTab.title)
        // Toolbar holds per-tab ACTIONS only (HIG: toolbars are for verbs, not
        // status). Connection state lives on the Home card + menu bar extra.
        // `.navigationTitle` already installs the window toolbar area, so the
        // Liquid Glass scroll edge effect works on every tab without a filler
        // item here.
        .toolbar {
            if selectedTab == .gallery {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        galleryService.clearAndReload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.isPL ? "Odśwież" : "Refresh")
                }
            }
            if selectedTab == .files {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        filesBrowserService.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.isPL ? "Odśwież" : "Refresh")
                }
            }
        }
    }
}
