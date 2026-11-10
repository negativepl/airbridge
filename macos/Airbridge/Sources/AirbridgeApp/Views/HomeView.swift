import SwiftUI
import Protocol

/// Home: the connected phone, laid out like a device page in System Settings —
/// a grouped `Form` with the device at the top, its details as labeled rows and
/// the connection action under the group. With several phones connected the
/// page is the active one, the phone the toolbar switcher names, and the rest
/// are rows underneath. Only system components: no custom cards, bars or
/// indicators.
struct HomeView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let pairingService: PairingService
    let bluetoothAudio: BluetoothAudioService

    @State private var viewModel: HomeViewModel
    @State private var showPairing = false

    init(
        connectionService: ConnectionService,
        fileTransferService: FileTransferService,
        pairingService: PairingService,
        bluetoothAudio: BluetoothAudioService
    ) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
        self.pairingService = pairingService
        self.bluetoothAudio = bluetoothAudio
        self._viewModel = State(initialValue: HomeViewModel(
            connectionService: connectionService,
            fileTransferService: fileTransferService
        ))
    }

    var body: some View {
        let vm = viewModel
        Group {
            if vm.isConnected, !vm.connectedDevices.isEmpty {
                devicesForm(vm)
            } else {
                unavailableView(vm)
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

    // MARK: - Connected

    private func devicesForm(_ vm: HomeViewModel) -> some View {
        // The page follows the active phone, so choosing another one, here or
        // in the toolbar, visibly swaps the whole page instead of moving a
        // checkmark between two identical stacks.
        let active = connectionService.activeDevice
        let others = vm.connectedDevices.filter { $0.connectionId != active?.connectionId }
        return Form {
            if let active {
                Section {
                    deviceHeader(active)
                }
                Section {
                    deviceDetails(active)
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { device in
                        LabeledContent {
                            Button(L10n.isPL ? "Używaj tego telefonu" : "Use This Phone") {
                                connectionService.setActiveDevice(device.connectionId)
                            }
                        } label: {
                            Text(displayName(device))
                            Text(statusText(device))
                        }
                    }
                } header: {
                    Text(L10n.isPL ? "Pozostałe urządzenia" : "Other Devices")
                } footer: {
                    Text(L10n.isPL
                        ? "Galeria, Pliki, Wiadomości i wysyłanie plików dotyczą wybranego telefonu."
                        : "Gallery, Files, Messages and sending files use the selected phone.")
                }
            }

            if vm.isTransferring {
                Section(L10n.fileTransfer) {
                    transferRow(vm)
                }
            }

            if bluetoothAudio.enabled, connectionService.phoneHeadphoneState?.connected == true {
                Section {
                    headphonesRow
                } footer: {
                    if connectionService.headphoneHandoffPhase == .failed {
                        Text(L10n.isPL
                            ? "Przeniesienie słuchawek nie powiodło się. Upewnij się, że słuchawki są włączone i sparowane z oboma urządzeniami."
                            : "Headphone handoff failed. Make sure the headphones are on and paired with both devices.")
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
            } footer: {
                HStack {
                    Spacer()
                    Button(L10n.disconnect) { vm.disconnect() }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.default, value: active?.connectionId)
    }

    /// The phone itself: its wallpaper as a square tile, the
    /// name as the page title and one line of status underneath.
    private func deviceHeader(_ device: ConnectedDevice) -> some View {
        VStack(spacing: 10) {
            if let data = device.wallpaper, let image = NSImage(data: data) {
                // Square tile: the wallpaper fills it and is cropped, so the
                // header keeps its size whatever the phone's proportions.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
            } else {
                Image(systemName: "smartphone")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            }
            Text(displayName(device))
                .font(.title2.bold())
            // Icon and text centred on one line with the same gap for every
            // item; a Label's fixed icon slot pushed the small dot down and away.
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(.green)
                    Text(L10n.isPL ? "Połączono" : "Connected")
                }
                if let info = device.deviceInfo {
                    HStack(spacing: 5) {
                        Image(systemName: batterySymbol(info))
                        Text("\(info.batteryPercent)%")
                            .contentTransition(.numericText())
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        // A different phone is a different header: it cross-fades as a whole
        // instead of morphing one wallpaper and name into the other.
        .id(device.connectionId)
        .transition(.opacity)
    }

    @ViewBuilder
    private func deviceDetails(_ device: ConnectedDevice) -> some View {
        if let info = device.deviceInfo {
            LabeledContent(L10n.isPL ? "Model" : "Model", value: "\(info.manufacturer) \(info.model)")
            LabeledContent("Android", value: info.androidVersion)
            LabeledContent(L10n.isPL ? "Bateria" : "Battery", value: batteryText(info))
            if info.totalStorageBytes > 0 {
                // Text only, like System Settings › General › About.
                LabeledContent(L10n.isPL ? "Pamięć" : "Storage",
                               value: L10n.isPL
                                   ? "\(Self.bytes(info.freeStorageBytes)) wolne z \(Self.bytes(info.totalStorageBytes))"
                                   : "\(Self.bytes(info.freeStorageBytes)) available of \(Self.bytes(info.totalStorageBytes))")
            }
        }
        if let ip = device.clientIP {
            LabeledContent(L10n.isPL ? "Adres IP" : "IP Address", value: ip)
        }
    }

    private func transferRow(_ vm: HomeViewModel) -> some View {
        ProgressView(value: vm.transferProgress) {
            Text(vm.transferFileName)
                .lineLimit(1)
                .truncationMode(.middle)
        } currentValueLabel: {
            Text([formatSpeed(vm.transferSpeed), formatEta(vm.transferEta)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                .contentTransition(.numericText())
        }
    }

    private var headphonesRow: some View {
        LabeledContent {
            Button(connectionService.headphoneHandoffPhase == .inProgress
                    ? (L10n.isPL ? "Przenoszenie…" : "Moving…")
                    : (L10n.isPL ? "Przenieś tutaj" : "Move Here")) {
                connectionService.takeoverHeadphones()
            }
            .disabled(connectionService.headphoneHandoffPhase == .inProgress)
        } label: {
            Label(L10n.isPL ? "Słuchawki są połączone z telefonem"
                            : "Headphones are connected to the phone",
                  systemImage: "headphones")
        }
    }

    // MARK: - Not connected

    @ViewBuilder
    private func unavailableView(_ vm: HomeViewModel) -> some View {
        if !vm.hasPairedDevices {
            ContentUnavailableView {
                Label(L10n.isPL ? "Brak sparowanych urządzeń" : "No Paired Devices", systemImage: "smartphone")
            } description: {
                Text(L10n.isPL ? "Sparuj telefon, aby rozpocząć." : "Pair your phone to get started.")
            } actions: {
                Button(L10n.pairDevice) { showPairing = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if vm.phase == .disconnected || vm.phase == .error {
            ContentUnavailableView {
                Label(vm.phase == .error ? vm.statusMessage : (L10n.isPL ? "Rozłączono" : "Disconnected"),
                      systemImage: "smartphone.slash")
            } description: {
                Text(L10n.isPL ? "Połącz ponownie, aby wznowić." : "Reconnect to resume.")
            } actions: {
                Button(L10n.reconnect) { vm.reconnect() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(L10n.isPL ? "Szukam telefonu" : "Looking for Your Phone", systemImage: "smartphone")
            } description: {
                VStack(spacing: 12) {
                    Text(L10n.isPL ? "Otwórz AirBridge na telefonie w tej samej sieci Wi-Fi."
                                   : "Open AirBridge on the phone on the same Wi-Fi network.")
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: - Formatting

    private func displayName(_ device: ConnectedDevice) -> String {
        if let name = device.deviceInfo?.name, !name.isEmpty { return name }
        return device.name
    }

    /// "Połączono · 61%": the one line under a phone that is not the active one.
    private func statusText(_ device: ConnectedDevice) -> String {
        let connected = L10n.isPL ? "Połączono" : "Connected"
        guard let info = device.deviceInfo else { return connected }
        return "\(connected) · \(info.batteryPercent)%"
    }

    /// "78% (Na baterii)" or "78% (Ładowanie, do pełna za 33 min)".
    private func batteryText(_ info: DeviceInfo) -> String {
        guard info.batteryCharging else {
            return "\(info.batteryPercent)% (" + (L10n.isPL ? "Na baterii" : "On battery") + ")"
        }
        var state = L10n.isPL ? "Ładowanie" : "Charging"
        if info.chargeTimeRemainingMs > 0 {
            let f = DateComponentsFormatter()
            f.unitsStyle = .short
            f.allowedUnits = [.hour, .minute]
            if let left = f.string(from: Double(info.chargeTimeRemainingMs) / 1000) {
                state += L10n.isPL ? ", do pełna za \(left)" : ", full in \(left)"
            }
        }
        return "\(info.batteryPercent)% (\(state))"
    }

    private func batterySymbol(_ info: DeviceInfo) -> String {
        if info.batteryCharging { return "battery.100percent.bolt" }
        switch info.batteryPercent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default:    return "battery.100percent"
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func formatSpeed(_ speed: Double) -> String {
        speed > 1024 ? ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s" : ""
    }

    private func formatEta(_ eta: Int) -> String {
        guard eta > 3 else { return "" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .short
        f.allowedUnits = [.minute, .second]
        return f.string(from: Double(eta)) ?? ""
    }
}

