import SwiftUI

struct MainWindow: View {
    @State private var selectedItem: NavigationItem = .home
    @State private var sidebarExpanded: Bool = true

    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    let fileTransferService: FileTransferService
    let pairingService: PairingService
    let historyService: HistoryService
    let galleryService: GalleryService
    let smsService: SmsService

    private var sidebarWidth: CGFloat {
        sidebarExpanded ? 200 : 48
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 2) {
                ForEach(NavigationItem.topItems) { item in
                    sidebarButton(item)
                }

                Spacer()

                ForEach(NavigationItem.bottomItems) { item in
                    sidebarButton(item)
                        .opacity(0.7)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
            .padding(.horizontal, 8)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .clipped()

            Divider()

            // Detail
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: sidebarExpanded)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    sidebarExpanded.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help(L10n.isPL ? "Przełącz pasek boczny" : "Toggle Sidebar")
            }
        }
        .navigationTitle(selectedItem.title)
    }

    @ViewBuilder
    private func sidebarButton(_ item: NavigationItem) -> some View {
        Button {
            selectedItem = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 15))
                    .frame(width: 22, height: 22)

                if sidebarExpanded {
                    Text(item.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, sidebarExpanded ? 10 : 0)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: sidebarExpanded ? .leading : .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedItem == item ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(selectedItem == item ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .home:
            HomeView(
                connectionService: connectionService,
                fileTransferService: fileTransferService,
                historyService: historyService,
                pairingService: pairingService
            )
        case .history:
            HistoryView(historyService: historyService)
        case .send:
            SendView(
                fileTransferService: fileTransferService,
                connectionService: connectionService,
                clipboardService: clipboardService
            )
        case .gallery:
            GalleryView(galleryService: galleryService, connectionService: connectionService)
        case .messages:
            MessagesView(smsService: smsService, connectionService: connectionService)
        case .settings:
            SettingsView(
                connectionService: connectionService,
                pairingService: pairingService
            )
        case .about:
            AboutView()
        }
    }
}
