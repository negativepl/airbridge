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

    /// User disconnected manually (phase-driven, no string matching).
    private var isDisconnected: Bool {
        viewModel.phase == .disconnected
    }

    private func indicatorState(_ vm: HomeViewModel) -> StatusIndicator.State {
        if !vm.hasPairedDevices { return .disconnected }
        switch vm.phase {
        case .connected: return .connected
        case .disconnected, .stopped: return .disconnected
        case .error: return .error
        case .starting, .listening: return .connecting
        }
    }

    /// Przyjazna nazwa telefonu (marketingowa z DeviceInfo, np. "Galaxy Z Fold7"),
    /// z fallbackiem do nazwy z parowania zanim przyjdzie device_info.
    private func connectedName(_ vm: HomeViewModel) -> String {
        if let name = vm.deviceInfo?.name, !name.isEmpty { return name }
        return vm.deviceName
    }

    private func connectionHeadline(_ vm: HomeViewModel) -> String {
        let n = vm.connectedDevices.count
        if n > 1 {
            return L10n.isPL ? "Połączono z \(n) urządzeniami" : "Connected to \(n) devices"
        }
        return L10n.isPL ? "Połączono z \(connectedName(vm))" : "Connected to \(connectedName(vm))"
    }

    private func connectedDetail(_ vm: HomeViewModel) -> String {
        var parts: [String] = []
        // With more than one device the per-device cards carry the model, so the
        // header summarises with just the Mac's network address.
        if vm.connectedDevices.count <= 1, let model = vm.deviceInfo?.model, !model.isEmpty {
            parts.append(model)
        }
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
                            Text(connectionHeadline(vm))
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
        } else if vm.phase == .error {
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
        // One card per connected phone — they stack instead of fighting over a
        // single slot, so two devices read as a list rather than flipping.
        VStack(spacing: 12) {
            ForEach(vm.connectedDevices) { device in
                singleDeviceCard(
                    info: device.deviceInfo,
                    wallpaper: device.wallpaper.flatMap { NSImage(data: $0) }
                )
            }
        }
    }

    @ViewBuilder
    private func singleDeviceCard(info: DeviceInfo?, wallpaper: NSImage?) -> some View {
        if wallpaper != nil || info != nil {
            GlassSection {
                HStack(alignment: .center, spacing: 18) {
                    if let img = wallpaper {
                        phonePreview(img, info: info)
                    }
                    if let info {
                        deviceInfoColumn(info)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func phonePreview(_ img: NSImage, info: DeviceInfo?) -> some View {
        // Fixed square tile: the wallpaper fills and is cropped to it, so the
        // card keeps its shape no matter what dimensions the phone reports.
        let side: CGFloat = 150
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(
                // Soft inner edge — clipped to the tile so the blur never
                // bleeds outside and shimmers against the glass background.
                shape
                    .strokeBorder(.black.opacity(0.25), lineWidth: 3)
                    .blur(radius: 2)
                    .clipShape(shape)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .overlay(alignment: .bottom) {
                if let info {
                    batteryPill(info.batteryPercent, charging: info.batteryCharging)
                        .padding(.bottom, 10)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .animation(.airbridgeQuick, value: info?.batteryPercent)
            .animation(.airbridgeQuick, value: info?.batteryCharging)
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
            // Power state intentionally has no row — the battery pill on the
            // wallpaper tile already shows percentage and a charging bolt.
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
