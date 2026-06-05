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
            if let info = vm.deviceInfo {
                deviceInfoCard(info)
            }
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

    private func connectionCard(_ vm: HomeViewModel) -> some View {
        GlassSection {
            HStack(spacing: 14) {
                StatusIndicator(state: indicatorState(vm), size: 18)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if vm.isConnected {
                            Text(vm.deviceName)
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
                        if vm.isConnected, let ip = vm.localIP {
                            Text(ip).contentTransition(.numericText())
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

    // MARK: - Device info

    private func deviceInfoCard(_ info: DeviceInfo) -> some View {
        GlassSection(
            title: LocalizedStringKey(info.name.isEmpty ? info.model : info.name),
            systemImage: "iphone"
        ) {
            infoRow(L10n.isPL ? "Model" : "Model", "\(info.manufacturer) \(info.model)")
            infoRow("Android", "\(info.androidVersion) · API \(info.sdkInt)")
            infoRow(L10n.isPL ? "Bateria" : "Battery", "\(info.batteryPercent)%")

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
