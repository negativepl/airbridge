import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let onFileDrop: () -> Void

    @AppStorage("islandWidth") private var islandWidth: Double = 756
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @State private var isTargeted = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            Group {
                if connectionService.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .padding(18)
            .frame(width: islandWidth, height: islandHeight)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: 24, style: .continuous)
            )
        }
        .shadow(radius: 40, y: 14)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onHover { _ in
            DropZonePopup.shared.resetAutoHideTimer()
        }
        .onChange(of: isTargeted) { _, _ in
            DropZonePopup.shared.resetAutoHideTimer()
        }
    }

    private var connectedContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                .symbolEffect(.bounce, value: isTargeted)

            Text(L10n.dropFileHere)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .glassEffect(
            isTargeted
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 18, style: .continuous)
        )
        .animation(.airbridgeQuick, value: isTargeted)
    }

    private var disconnectedContent: some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.noDeviceConnected)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard connectionService.isConnected else { return false }
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                fileTransferService.sendFile(url: url)
                onFileDrop()
            }
        }
        return true
    }
}
