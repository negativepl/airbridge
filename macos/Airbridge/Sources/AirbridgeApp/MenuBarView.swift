import SwiftUI
import Protocol

struct MenuBarView: View {
    let connectionService: ConnectionService
    let clipboardService: ClipboardService
    let updateService: UpdateService
    let bluetoothAudio: BluetoothAudioService
    @Environment(\.openWindow) private var openWindow
    @State private var showHandoffSuccess = false

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
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

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
                    .padding(.horizontal, 14)
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

                if bluetoothAudio.enabled,
                   connectionService.phoneHeadphoneState?.connected == true
                        || connectionService.headphoneHandoffPhase == .inProgress
                        || showHandoffSuccess {
                    MenuRow(title: showHandoffSuccess
                                ? (L10n.isPL ? "Słuchawki połączone z Makiem" : "Headphones connected to Mac")
                                : (connectionService.headphoneHandoffPhase == .inProgress
                                    ? (L10n.isPL ? "Przenoszenie słuchawek…" : "Moving headphones…")
                                    : (L10n.isPL ? "Przenieś słuchawki na Maca" : "Move headphones to Mac")),
                            systemImage: showHandoffSuccess ? "checkmark.circle" : "headphones",
                            loading: !showHandoffSuccess && connectionService.headphoneHandoffPhase == .inProgress) {
                        guard !showHandoffSuccess, connectionService.headphoneHandoffPhase != .inProgress else { return }
                        connectionService.takeoverHeadphones()
                    }
                } else if bluetoothAudio.enabled, bluetoothAudio.selectedConnected {
                    // Headphones already on this Mac: passive status row. Shares
                    // MenuRow's exact geometry (spacing/font/padding/minHeight) so
                    // the morph from the actionable row is in-place — only the
                    // label text and tone change, no horizontal jump or resize.
                    HStack(spacing: 8) {
                        Image(systemName: "headphones")
                            .font(.ab(.subheadline))
                            .frame(width: 18, alignment: .center)
                            .foregroundStyle(.secondary)
                        Text(L10n.isPL ? "Słuchawki połączone z Makiem" : "Headphones connected to Mac")
                            .font(.ab(.subheadline))
                            .foregroundStyle(.primary.opacity(0.75))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .padding(.horizontal, 6)
                }

                Divider()
                    .padding(.horizontal, 8)
            }

            MenuRow(title: L10n.openAirbridge, systemImage: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuRow(title: L10n.isPL ? "Sprawdź aktualizacje" : "Check for updates",
                    systemImage: "arrow.triangle.2.circlepath",
                    loading: updateService.phase == .checking,
                    trailing: { AnyView(updateRowTrailing) }) {
                switch updateService.phase {
                case .idle, .failed:
                    Task { await updateService.checkForUpdates() }
                case .available:
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                case .checking, .upToDate, .downloading, .installing:
                    break
                }
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
        // Size to content like a native NSMenu: the frame goes FIRST so it only
        // raises the floor, then fixedSize collapses the whole stack to its ideal
        // (content) width. With the frame outermost it would instead absorb the
        // window's full proposed width clamped to maxWidth — always maximal.
        .frame(minWidth: 220)
        .fixedSize(horizontal: true, vertical: false)
        // No row/layout animations on purpose: native NSMenus never animate
        // their items, and animated inserts inside a fixedSize popover read as
        // the menu "jumping". State changes swap content instantly.
        .onChange(of: connectionService.headphoneHandoffPhase) { old, new in
            if old == .inProgress && new == .idle {
                showHandoffSuccess = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    showHandoffSuccess = false
                }
            }
        }
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

    /// Mirrors `AboutTabView.updateRowTrailing` — compact status readout next
    /// to the "Check for updates" row.
    @ViewBuilder
    private var updateRowTrailing: some View {
        switch updateService.phase {
        case .idle:
            EmptyView()

        case .checking:
            // Spinner lives in the row's leading icon slot (MenuRow.loading);
            // nothing on the right, so the row width stays put.
            EmptyView()

        case .upToDate:
            Text(L10n.isPL ? "Aktualne" : "Up to date")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.green)
                .lineLimit(1)

        case .available(let manifest):
            Text(L10n.isPL ? "Dostępna: \(manifest.version)" : "Available: \(manifest.version)")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)

        case .downloading, .installing:
            ProgressView()
                .controlSize(.small)

        case .failed:
            Text(L10n.isPL ? "Błąd" : "Failed")
                .font(.ab(.caption, weight: .semibold))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
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
    /// Swap the leading icon for a small spinner in the same 18pt slot, so a
    /// busy row never changes width — only the icon and title change.
    var loading: Bool = false
    var trailing: () -> AnyView = { AnyView(EmptyView()) }
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if loading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: systemImage)
                        .font(.ab(.subheadline))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 18, height: 18, alignment: .center)
            Text(title)
                .font(.ab(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 6)
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
