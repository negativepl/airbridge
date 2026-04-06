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
        ZStack {
            // Black background filling whole window
            BottomRoundedShape(radius: islandCornerRadius)
                .fill(Color.black)

            if connectionService.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .center)
        .clipShape(BottomRoundedShape(radius: islandCornerRadius))
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
        ZStack {
            UShape(cornerRadius: islandCornerRadius)
                .stroke(style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 2, dash: [8, 4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.25))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .scaleEffect(isTargeted ? 1.015 : 1.0)
                .allowsHitTesting(false)

            HStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                Text(L10n.dropFileHere)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 18)
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTargeted)
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

// MARK: - UShape

/// Open-top rounded shape — left side, rounded bottom, right side. No top edge.
struct UShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
