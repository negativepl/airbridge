import SwiftUI
import Protocol

struct HomeView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let pairingService: PairingService

    @State private var viewModel: HomeViewModel
    @State private var showPairing = false

    init(
        connectionService: ConnectionService,
        fileTransferService: FileTransferService,
        pairingService: PairingService
    ) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
        self.pairingService = pairingService
        self._viewModel = State(initialValue: HomeViewModel(
            connectionService: connectionService,
            fileTransferService: fileTransferService
        ))
    }

    var body: some View {
        let vm = viewModel
        VStack(spacing: 16) {
            connectionCard(vm)
            if vm.isTransferring {
                transferCard(vm)
            }
            deviceCard(vm)
            if !vm.hasPairedDevices {
                noPairedDevicesCard
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingView(
                pairingService: pairingService,
                connectionService: connectionService,
                isPresented: $showPairing
            )
        }
        .task {
            // Odświeżaj DeviceInfo co 10 s, by stan/czas ładowania był na żywo.
            while !Task.isCancelled {
                if connectionService.isConnected {
                    connectionService.requestDeviceInfo()
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private var isDisconnected: Bool {
        viewModel.statusMessage.contains("Rozłączono") || viewModel.statusMessage.contains("Disconnected")
    }

    private func indicatorState(_ vm: HomeViewModel) -> StatusIndicator.State {
        if vm.isConnected { return .connected }
        if !vm.hasPairedDevices { return .disconnected }
        if isDisconnected { return .disconnected }
        if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Failed") || vm.statusMessage.contains("Błąd") {
            return .error
        }
        return .connecting
    }

    /// Przyjazna nazwa telefonu (marketingowa z DeviceInfo, np. "Galaxy Z Fold7"),
    /// z fallbackiem do nazwy z parowania zanim przyjdzie device_info.
    private func connectedName(_ vm: HomeViewModel) -> String {
        if let name = vm.deviceInfo?.name, !name.isEmpty { return name }
        return vm.deviceName
    }

    private func connectedDetail(_ vm: HomeViewModel) -> String {
        var parts: [String] = []
        if let model = vm.deviceInfo?.model, !model.isEmpty { parts.append(model) }
        if let ip = vm.localIP { parts.append(ip) }
        return parts.joined(separator: " · ")
    }

    private func connectionCard(_ vm: HomeViewModel) -> some View {
        GlassSection {
            HStack(spacing: 14) {
                StatusIndicator(state: indicatorState(vm), size: 18)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if vm.isConnected {
                            Text(L10n.isPL
                                ? "Połączono z \(connectedName(vm))"
                                : "Connected to \(connectedName(vm))")
                        } else if !vm.hasPairedDevices {
                            Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                        } else if isDisconnected {
                            Text(L10n.isPL ? "Rozłączono" : "Disconnected")
                        } else {
                            Text(vm.statusMessage)
                        }
                    }
                    .font(.ab(.headline, weight: .semibold))
                    .contentTransition(.interpolate)

                    Group {
                        if vm.isConnected {
                            Text(connectedDetail(vm)).contentTransition(.numericText())
                        } else if !vm.hasPairedDevices {
                            Text(L10n.isPL ? "Sparuj telefon aby rozpocząć" : "Pair your phone to get started")
                        } else if isDisconnected {
                            Text(L10n.isPL ? "Kliknij Połącz ponownie aby wznowić" : "Click Reconnect to resume")
                        } else if !vm.isConnected {
                            Text(L10n.isPL ? "Szukam sparowanego urządzenia…" : "Looking for paired device…")
                        }
                    }
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                connectionActionButton(vm)
            }
            .animation(.airbridgeQuick, value: vm.isConnected)
            .animation(.airbridgeQuick, value: vm.statusMessage)
        }
    }

    @ViewBuilder
    private func connectionActionButton(_ vm: HomeViewModel) -> some View {
        if vm.isConnected {
            Button(L10n.disconnect) { vm.disconnect() }
                .controlSize(.extraLarge)
        } else if isDisconnected {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        } else if !vm.hasPairedDevices {
            Button(L10n.pairDevice) { showPairing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Błąd") {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.extraLarge)
        }
    }

    private func transferCard(_ vm: HomeViewModel) -> some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "arrow.down.circle") {
            Text(vm.transferFileName)
                .font(.ab(.body))
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: vm.transferProgress)
                .tint(.accentColor)

            HStack {
                Text(formatSpeed(vm.transferSpeed))
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Text(formatEta(vm.transferEta))
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var noPairedDevicesCard: some View {
        GlassSection {
            VStack(spacing: 14) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
                Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                    .font(.ab(.body))
                    .foregroundStyle(.secondary)
                Button(L10n.pairDevice) { showPairing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Device card (Phone Link-style: wallpaper preview + info)

    @ViewBuilder
    private func deviceCard(_ vm: HomeViewModel) -> some View {
        let wallpaper = vm.isConnected ? connectionService.phoneWallpaper.flatMap { NSImage(data: $0) } : nil
        if wallpaper != nil || vm.deviceInfo != nil {
            GlassSection {
                HStack(alignment: .center, spacing: 18) {
                    if let img = wallpaper {
                        phonePreview(img, vm: vm)
                    }
                    if let info = vm.deviceInfo {
                        deviceInfoColumn(info)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func phonePreview(_ img: NSImage, vm: HomeViewModel) -> some View {
        let aspect = img.size.width / max(img.size.height, 1)
        let width: CGFloat = 150
        let height = min(max(width / max(aspect, 0.01), 110), 280)
        return Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) {
                if let info = vm.deviceInfo {
                    batteryPill(info.batteryPercent, charging: info.batteryCharging)
                        .padding(.bottom, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 3)
                    .blur(radius: 2)
                    .padding(-1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .animation(.airbridgeQuick, value: vm.deviceInfo?.batteryPercent)
            .animation(.airbridgeQuick, value: vm.deviceInfo?.batteryCharging)
    }

    private func batteryPill(_ percent: Int, charging: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: batterySymbol(percent))
            Text("\(percent)%")
                .contentTransition(.numericText())
            if charging {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
            }
        }
        .font(.ab(.caption2, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default:    return "battery.100percent"
        }
    }

    // MARK: - Device info column

    @ViewBuilder
    private func deviceInfoColumn(_ info: DeviceInfo) -> some View {
        VStack(spacing: 12) {
            infoRow(L10n.isPL ? "Model" : "Model", "\(info.manufacturer) \(info.model)")

            usageRow(
                label: L10n.isPL ? "Pamięć" : "Storage",
                freeBytes: info.freeStorageBytes,
                totalBytes: info.totalStorageBytes
            )
            usageRow(
                label: "RAM",
                freeBytes: info.freeRamBytes,
                totalBytes: info.totalRamBytes
            )
            infoRow(L10n.isPL ? "Zasilanie" : "Power", Self.powerText(info))
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.ab(.body))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.ab(.body))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func usageRow(label: String, freeBytes: Int64, totalBytes: Int64) -> some View {
        let used = max(0, totalBytes - freeBytes)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.ab(.body))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.isPL
                     ? "\(Self.bytes(freeBytes)) wolne z \(Self.bytes(totalBytes))"
                     : "\(Self.bytes(freeBytes)) free of \(Self.bytes(totalBytes))")
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if totalBytes > 0 {
                ProgressView(value: Double(used), total: Double(totalBytes))
                    .tint(.accentColor)
            }
        }
    }

    private static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f.string(fromByteCount: value)
    }

    private static func powerText(_ info: DeviceInfo) -> String {
        let isPL = L10n.isPL
        guard info.batteryCharging else {
            return isPL ? "Na baterii" : "On battery"
        }
        if info.chargeTimeRemainingMs > 0 {
            let t = formatChargeTime(info.chargeTimeRemainingMs, isPL: isPL)
            return isPL ? "Ładowanie · \(t) do pełna" : "Charging · \(t) to full"
        }
        return isPL ? "Ładowanie" : "Charging"
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed > 1024 * 1024 { return String(format: "%.1f MB/s", speed / (1024 * 1024)) }
        else if speed > 1024 { return String(format: "%.0f KB/s", speed / 1024) }
        return ""
    }

    private func formatEta(_ eta: Int) -> String {
        if eta > 60 { return "\(eta / 60) min \(eta % 60) s" }
        else if eta > 3 { return "\(eta) s" }
        return ""
    }
}
