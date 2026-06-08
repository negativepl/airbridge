import SwiftUI

struct MenuBarView: View {
    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusIndicator(state: connectionService.isConnected ? .connected : .disconnected, size: 12)
                if connectionService.isConnected {
                    Text("\(L10n.connectedToDevice) \(connectionService.connectedDeviceName)")
                        .font(.subheadline)
                } else {
                    Text(L10n.notConnected).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if connectionService.isConnected, let info = connectionService.deviceInfo {
                BatteryRow(percent: info.batteryPercent, charging: info.batteryCharging)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Divider()
                .padding(.horizontal, 8)

            if connectionService.isConnected {
                MenuRow(title: L10n.isPL ? "Zadzwoń na telefon" : "Ring phone",
                        systemImage: "iphone.radiowaves.left.and.right") {
                    connectionService.ringPhone()
                }
            }

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

/// Wiersz baterii telefonu w rozwijanym menu paska.
private struct BatteryRow: View {
    let percent: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.ab(.subheadline))
                .frame(width: 18, alignment: .center)
                .foregroundStyle(charging ? Color.green : Color.primary)
            Text(label)
                .font(.ab(.subheadline))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var label: String {
        if charging {
            return L10n.isPL ? "Bateria \(percent)% • ładowanie" : "Battery \(percent)% • charging"
        }
        return L10n.isPL ? "Bateria \(percent)%" : "Battery \(percent)%"
    }

    private var symbol: String {
        switch percent {
        case ...10: return "battery.0"
        case ...37: return "battery.25"
        case ...62: return "battery.50"
        case ...87: return "battery.75"
        default:    return "battery.100"
        }
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
                .font(.ab(.subheadline))
                .frame(width: 18, alignment: .center)
                .foregroundStyle(.primary)
            Text(title)
                .font(.ab(.subheadline))
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
