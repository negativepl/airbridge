import SwiftUI

struct HomeView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let historyService: HistoryService
    let pairingService: PairingService

    @State private var viewModel: HomeViewModel
    @State private var showPairing = false

    init(
        connectionService: ConnectionService,
        fileTransferService: FileTransferService,
        historyService: HistoryService,
        pairingService: PairingService
    ) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
        self.historyService = historyService
        self.pairingService = pairingService
        self._viewModel = State(initialValue: HomeViewModel(
            connectionService: connectionService,
            fileTransferService: fileTransferService,
            historyService: historyService
        ))
    }

    var body: some View {
        let vm = viewModel
        VStack(spacing: 16) {
            connectionCard(vm)
            if vm.isTransferring {
                transferCard(vm)
            }
            if vm.hasPairedDevices {
                recentActivityCard(vm)
            } else {
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
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 13))
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
                .controlSize(.large)
        } else if isDisconnected {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if !vm.hasPairedDevices {
            Button(L10n.pairDevice) { showPairing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Błąd") {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
        }
    }

    private func transferCard(_ vm: HomeViewModel) -> some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "arrow.down.circle") {
            Text(vm.transferFileName)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: vm.transferProgress)
                .tint(.accentColor)

            HStack {
                Text(formatSpeed(vm.transferSpeed))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Text(formatEta(vm.transferEta))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func recentActivityCard(_ vm: HomeViewModel) -> some View {
        GlassSection(
            title: LocalizedStringKey(L10n.isPL ? "Ostatnia aktywność" : "Recent Activity"),
            systemImage: "clock"
        ) {
            let items = vm.recentActivity
            if items.isEmpty {
                Text(L10n.isPL ? "Brak aktywności" : "No activity yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { record in
                    HStack(spacing: 8) {
                        Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc")
                            .foregroundStyle(record.direction == .sent ? Color.primary : Color.accentColor)
                        Text(record.description)
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                        Text(record.timestamp, style: .relative)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
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
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button(L10n.pairDevice) { showPairing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
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
