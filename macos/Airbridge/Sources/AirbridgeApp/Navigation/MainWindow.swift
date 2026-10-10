import SwiftUI
import Mirror

struct MainWindow: View {
    @State private var selectedTab: NavigationItem = .home
    @Environment(\.openWindow) private var openWindow
    @AppStorage("files.viewMode") private var filesViewModeRaw: String = FileViewMode.list.rawValue

    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    let fileTransferService: FileTransferService
    let pairingService: PairingService
    let galleryService: GalleryService
    let smsService: SmsService
    let filesBrowserService: FilesBrowserService
    let notificationService: NotificationService
    let hotkeyService: GlobalHotkeyService
    let mirrorService: MirrorService
    let updateService: UpdateService
    let bluetoothAudioService: BluetoothAudioService

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(NavigationItem.home.title, systemImage: "house.fill", value: .home) {
                ScreenContainer(scroll: false) {
                    HomeView(
                        connectionService: connectionService,
                        fileTransferService: fileTransferService,
                        pairingService: pairingService,
                        bluetoothAudio: bluetoothAudioService
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
                        hotkeyService: hotkeyService,
                        notificationService: notificationService,
                        updateService: updateService,
                        bluetoothAudio: bluetoothAudioService
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // The window keeps room for the sidebar even while it is hidden, so
        // showing it never has to grow a squeezed window in one jump. SwiftUI
        // sets the window's minimum to the detail minimum alone whenever the
        // sidebar hides, so it is raised again as a resize begins.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willStartLiveResizeNotification)) { note in
            guard let window = note.object as? NSWindow, window.identifier?.rawValue.hasPrefix("main") == true else { return }
            let minWidth = ScreenMetrics.minDetailWidth + ScreenMetrics.sidebarWidth
            if window.contentMinSize.width < minWidth { window.contentMinSize.width = minWidth }
        }
        .navigationTitle(selectedTab.title)
        // Toolbar holds per-tab ACTIONS only (HIG: toolbars are for verbs, not
        // status). Connection state lives on the Home card + menu bar extra.
        // `.navigationTitle` already installs the window toolbar area, so the
        // Liquid Glass scroll edge effect works on every tab without a filler
        // item here.
        .toolbar {
            // Active-device switcher — drives which phone Gallery/Files/SMS/send
            // target. Trailing edge (right), shown only when more than one phone
            // is connected; with one, everything just targets it.
            if connectionService.connectedDevices.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(connectionService.connectedDevices) { device in
                            Button {
                                connectionService.setActiveDevice(device.connectionId)
                            } label: {
                                if device.connectionId == connectionService.activeDeviceId {
                                    Label(deviceLabel(device), systemImage: "checkmark")
                                } else {
                                    Text(deviceLabel(device))
                                }
                            }
                        }
                    } label: {
                        // Custom label so the value and chevron get real internal
                        // padding instead of hugging the pill edges.
                        HStack(spacing: 6) {
                            Image(systemName: "iphone").foregroundStyle(.secondary)
                            Text(activeDeviceLabel).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                    .menuIndicator(.hidden)
                    .help(L10n.isPL ? "Aktywne urządzenie dla galerii, plików, SMS i wysyłki" : "Active device for gallery, files, SMS and sending")
                }
                ToolbarSpacer(.fixed)
            }
            if selectedTab == .files {
                // One consolidated options menu instead of three separate items —
                // alongside the device switcher and the search field they would
                // otherwise overflow into the toolbar's ">>" collapse.
                ToolbarItem(placement: .primaryAction) {
                    filesOptionsMenu
                }
            }
            if selectedTab == .mirror && mirrorService.isStreaming {
                // Native toolbar items — macOS sizes, styles and glass-groups
                // them itself (like Notes). No custom glass/frames.
                ToolbarItem(placement: .primaryAction) {
                    Text("\(Int(mirrorService.decodedFramesPerSecond)) FPS · \(String(format: "%.1f", mirrorService.incomingBitrateMbps)) Mbps")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openWindow(id: "mirror")
                    } label: {
                        Label(L10n.isPL ? "Wydziel okno" : "Pop out", systemImage: "macwindow.on.rectangle")
                    }
                    .help(L10n.isPL ? "Otwórz w osobnym oknie" : "Open in a separate window")
                }
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { try? await connectionService.broadcast(.mirrorStop) }
                    } label: {
                        Label(L10n.isPL ? "Zatrzymaj" : "Stop", systemImage: "stop.fill")
                    }
                    .help(L10n.isPL ? "Zatrzymaj udostępnianie" : "Stop sharing")
                }
            }
        }
    }

    /// Marketing name ("Galaxy Z Fold7") with a fallback to the pairing name.
    private func deviceLabel(_ device: ConnectedDevice) -> String {
        if let n = device.deviceInfo?.name, !n.isEmpty { return n }
        return device.name
    }

    private var activeDeviceLabel: String {
        connectionService.activeDevice.map { deviceLabel($0) }
            ?? (L10n.isPL ? "Urządzenie" : "Device")
    }

    // View mode + sorting + refresh folded into one toolbar menu so the Files
    // toolbar stays compact next to the device switcher and the search field.
    private var filesOptionsMenu: some View {
        Menu {
            Picker(L10n.isPL ? "Widok" : "View",
                   selection: Binding(get: { FileViewMode(rawValue: filesViewModeRaw) ?? .list },
                                      set: { filesViewModeRaw = $0.rawValue })) {
                Label(L10n.isPL ? "Lista" : "List", systemImage: "list.bullet").tag(FileViewMode.list)
                Label(L10n.isPL ? "Siatka" : "Grid", systemImage: "square.grid.2x2").tag(FileViewMode.grid)
            }
            Divider()
            Picker(L10n.isPL ? "Sortuj wg" : "Sort by",
                   selection: Binding(get: { filesBrowserService.sortBy },
                                      set: { filesBrowserService.sortBy = $0 })) {
                Text(L10n.isPL ? "Nazwa" : "Name").tag(FileSortKey.name)
                Text(L10n.isPL ? "Rozmiar" : "Size").tag(FileSortKey.size)
                Text(L10n.isPL ? "Data modyfikacji" : "Date modified").tag(FileSortKey.modified)
                Text(L10n.isPL ? "Typ" : "Type").tag(FileSortKey.type)
            }
            Picker(L10n.isPL ? "Kierunek" : "Order",
                   selection: Binding(get: { filesBrowserService.sortAscending },
                                      set: { filesBrowserService.sortAscending = $0 })) {
                Text(L10n.isPL ? "Rosnąco" : "Ascending").tag(true)
                Text(L10n.isPL ? "Malejąco" : "Descending").tag(false)
            }
            Toggle(L10n.isPL ? "Foldery na początku" : "Folders first",
                   isOn: Binding(get: { filesBrowserService.foldersFirst },
                                 set: { filesBrowserService.foldersFirst = $0 }))
            Divider()
            Button {
                filesBrowserService.reload()
            } label: {
                Label(L10n.isPL ? "Odśwież" : "Refresh", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel(L10n.isPL ? "Opcje" : "Options")
        }
        .help(L10n.isPL ? "Widok, sortowanie, odświeżanie" : "View, sorting and refresh")
    }
}
