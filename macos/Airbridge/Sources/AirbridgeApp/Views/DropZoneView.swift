import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let onFileDrop: () -> Void

    @AppStorage("islandWidth") private var islandWidth: Double = 756
    @AppStorage("islandHeight") private var islandHeight: Double = 130
    @AppStorage("islandCornerRadius") private var islandCornerRadius: Double = 24

    @State private var isTargeted = false

    var body: some View {
        Group {
            if connectionService.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
        .frame(width: islandWidth, height: islandHeight, alignment: .center)
        .clipShape(BottomRoundedShape(radius: islandCornerRadius))
        .background(
            BottomRoundedShape(radius: islandCornerRadius)
                .fill(Color.black)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var connectedContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.2))
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 4)

            HStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isTargeted ? Color.accentColor : .white.opacity(0.6))
                Text(L10n.dropFileHere)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isTargeted ? .white : .white.opacity(0.7))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private var disconnectedContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
            Text(L10n.noDeviceConnected)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
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
