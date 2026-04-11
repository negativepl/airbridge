import SwiftUI

struct MenuBarView: View {
    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionService.isConnected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                if connectionService.isConnected {
                    Text("\(L10n.connectedToDevice) \(connectionService.connectedDeviceName)")
                        .font(.subheadline)
                } else {
                    Text(L10n.notConnected).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            MenuRow(title: L10n.openAirbridge, systemImage: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuRow(title: L10n.quit, systemImage: "xmark.circle") {
                clipboardService.stopMonitoring()
                connectionService.stopServer()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 260)
    }
}

/// Native-feeling menu row for MenuBarExtra popover body. Matches the hover
/// treatment of system menu extras (Wi-Fi, Bluetooth, Control Center) on
/// macOS 14+ / Tahoe:
///
/// - Flat by default, no background, no glass tint
/// - Hover: subtle `.primary.opacity(0.08)` fill, foreground unchanged
/// - Pressed: slightly darker `.primary.opacity(0.14)`
/// - cornerRadius 8 — matches the popover's internal content radius
/// - Full-width minus an 8pt horizontal inset so the hover fill sits nicely
///   inside the popover's own rounded border
private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 18, alignment: .center)
                .foregroundStyle(.primary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    action()
                }
        )
    }

    private var backgroundFill: Color {
        if isPressed { return Color.primary.opacity(0.14) }
        if isHovered { return Color.primary.opacity(0.08) }
        return .clear
    }
}
