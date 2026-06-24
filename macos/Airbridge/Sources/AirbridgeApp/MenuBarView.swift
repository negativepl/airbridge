import SwiftUI
import Protocol

struct MenuBarView: View {
    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusIndicator(state: connectionService.isConnected ? .connected : .disconnected, size: 12)
                    .frame(width: 18, alignment: .center)
                if connectionService.isConnected {
                    Text(connectionHeadline)
                        .font(.ab(.subheadline))
                        .lineLimit(1)
                } else {
                    Text(L10n.notConnected).font(.ab(.subheadline)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            let devices = connectionService.connectedDevices
            if !devices.isEmpty {
                Divider()
                    .padding(.horizontal, 8)

                if devices.count > 1 {
                    // Tap a device to make it the active target (ring, send, etc.).
                    // The active one is bold and floated to the top.
                    let activeId = connectionService.activeDeviceId
                    let ordered = devices.filter { $0.connectionId == activeId }
                        + devices.filter { $0.connectionId != activeId }
                    ForEach(ordered) { device in
                        DeviceSelectRow(
                            name: menuDeviceName(device),
                            info: device.deviceInfo,
                            isActive: device.connectionId == activeId,
                            onSelect: { connectionService.setActiveDevice(device.connectionId) }
                        )
                    }
                } else if let info = devices.first?.deviceInfo {
                    BatteryRow(
                        percent: info.batteryPercent,
                        charging: info.batteryCharging,
                        chargeTimeRemainingMs: info.chargeTimeRemainingMs
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                }
            }

            Divider()
                .padding(.horizontal, 8)

            if connectionService.isConnected {
                if connectionService.isRinging {
                    MenuRow(title: L10n.isPL ? "Zatrzymaj dzwonienie" : "Stop ringing",
                            systemImage: "bell.slash") {
                        connectionService.stopRingPhone()
                    }
                } else {
                    MenuRow(title: ringTitle,
                            systemImage: "iphone.radiowaves.left.and.right") {
                        connectionService.ringPhone()
                    }
                }

                Divider()
                    .padding(.horizontal, 8)
            }

            MenuRow(title: L10n.openAirbridge, systemImage: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuRow(title: L10n.quit, systemImage: "xmark.circle") {
                clipboardService.stopMonitoring()
                Task {
                    await connectionService.stopServer()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.vertical, 6)
        // Size to content (narrow for short names, wide for long ones) instead of
        // a fixed width, clamped so it is never cramped nor absurdly wide.
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 240, maxWidth: 420)
    }

    private var connectionHeadline: String {
        let devices = connectionService.connectedDevices
        if devices.count > 1 {
            return L10n.isPL ? "Połączono z \(devices.count) urządzeniami" : "Connected to \(devices.count) devices"
        }
        let name = devices.first.map { menuDeviceName($0) } ?? connectionService.connectedDeviceName
        return "\(L10n.connectedToDevice) \(name)"
    }

    /// Marketing name from device info ("Galaxy Z Fold7") with a fallback to the
    /// pairing name before device_info arrives.
    private func menuDeviceName(_ device: ConnectedDevice) -> String {
        if let n = device.deviceInfo?.name, !n.isEmpty { return n }
        return device.name
    }

    /// Ring action names the active device when more than one is connected, so it
    /// is clear which phone will ring.
    private var ringTitle: String {
        if connectionService.connectedDevices.count > 1, let active = connectionService.activeDevice {
            let name = menuDeviceName(active)
            return L10n.isPL ? "Zadzwoń: \(name)" : "Ring \(name)"
        }
        return L10n.isPL ? "Zadzwoń na telefon" : "Ring phone"
    }
}

/// Selectable device row in the menu popover: battery + name, tap to make active,
/// checkmark on the current target.
private struct DeviceSelectRow: View {
    let name: String
    let info: DeviceInfo?
    let isActive: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.map { menuBatterySymbol($0.batteryPercent) } ?? "iphone")
                .font(.ab(.subheadline))
                .frame(width: 18, alignment: .center)
                .foregroundStyle((info?.batteryCharging ?? false) ? Color.green : Color.primary)
            Text(label)
                .font(.ab(.subheadline, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }

    private var label: String {
        guard let info else { return name }
        let charge = info.batteryCharging ? (L10n.isPL ? " • ładowanie" : " • charging") : ""
        return "\(name) • \(info.batteryPercent)%\(charge)"
    }
}

private func menuBatterySymbol(_ percent: Int) -> String {
    switch percent {
    case ...10: return "battery.0"
    case ...37: return "battery.25"
    case ...62: return "battery.50"
    case ...87: return "battery.75"
    default:    return "battery.100"
    }
}

/// Wiersz baterii telefonu w rozwijanym menu paska.
private struct BatteryRow: View {
    var deviceName: String? = nil
    let percent: Int
    let charging: Bool
    let chargeTimeRemainingMs: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.ab(.subheadline))
                .frame(width: 18, alignment: .center)
                .foregroundStyle(charging ? Color.green : Color.primary)
            Text(label)
                .font(.ab(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var label: String {
        // Multi-device rows are prefixed with the (long) device name, so use a
        // compact battery form there — "Name • 95%" — and drop the "Battery" word
        // and the charge-time detail that would otherwise truncate.
        if let deviceName {
            let charge = charging ? (L10n.isPL ? " • ładowanie" : " • charging") : ""
            return "\(deviceName) • \(percent)%\(charge)"
        }
        if charging {
            if chargeTimeRemainingMs > 0 {
                let t = formatChargeTime(chargeTimeRemainingMs, isPL: L10n.isPL)
                return L10n.isPL ? "Bateria \(percent)% • \(t) do pełna" : "Battery \(percent)% • \(t) to full"
            }
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
