import SwiftUI

struct HomeView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let historyService: HistoryService
    let pairingService: PairingService

    @State private var viewModel: HomeViewModel?
    @State private var showPairing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let vm = viewModel {
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
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    connectionService: connectionService,
                    fileTransferService: fileTransferService,
                    historyService: historyService
                )
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

    private func connectionCard(_ vm: HomeViewModel) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                if vm.isConnected {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                } else if !vm.hasPairedDevices {
                    Circle().fill(Color.gray).frame(width: 10, height: 10)
                } else if vm.statusMessage.contains("Starting") || vm.statusMessage.contains("Waiting") {
                    ProgressView().controlSize(.small)
                } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Failed") {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                } else {
                    Circle().fill(Color.orange).frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if vm.isConnected {
                        Text(vm.deviceName).font(.headline)
                    } else if !vm.hasPairedDevices {
                        Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                            .font(.headline)
                    } else {
                        Text(vm.statusMessage).font(.headline)
                    }
                    if vm.isConnected, let ip = vm.localIP {
                        Text(ip).font(.caption).foregroundStyle(.secondary)
                    } else if !vm.hasPairedDevices {
                        Text(L10n.isPL ? "Sparuj telefon aby rozpocząć" : "Pair your phone to get started")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !vm.isConnected {
                        Text(L10n.isPL ? "Szukam sparowanego urządzenia…" : "Looking for paired device…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if vm.isConnected {
                    Button(L10n.disconnect) { vm.disconnect() }
                } else if !vm.hasPairedDevices {
                    Button(L10n.pairDevice) { showPairing = true }
                        .controlSize(.large)
                } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Stopped") {
                    Button(L10n.reconnect) { vm.reconnect() }
                        .controlSize(.large)
                }
            }
            .padding(4)
        } label: {
            Label(L10n.connection, systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    private func transferCard(_ vm: HomeViewModel) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.transferFileName)
                    .font(.subheadline).lineLimit(1)
                ProgressView(value: vm.transferProgress)
                HStack {
                    Text(formatSpeed(vm.transferSpeed))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatEta(vm.transferEta))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Label(L10n.fileTransfer, systemImage: "arrow.down.circle")
        }
    }

    private func recentActivityCard(_ vm: HomeViewModel) -> some View {
        GroupBox {
            recentActivityContent(vm)
        } label: {
            Label(L10n.isPL ? "Ostatnia aktywność" : "Recent Activity", systemImage: "clock")
        }
    }

    @ViewBuilder
    private func recentActivityContent(_ vm: HomeViewModel) -> some View {
        let items = vm.recentActivity
        if items.isEmpty {
            Text(L10n.isPL ? "Brak aktywności" : "No activity yet")
                .font(.subheadline).foregroundStyle(.secondary).padding(4)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { record in
                    recentActivityRow(record)
                }
            }
        }
    }

    private func recentActivityRow(_ record: TransferRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc")
                .foregroundStyle(record.direction == .sent ? Color.primary : Color.accentColor)
            Text(record.description).font(.subheadline).lineLimit(1)
            Spacer()
            Text(record.timestamp, style: .relative)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    private var noPairedDevicesCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 32)).foregroundStyle(.secondary)
                Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(L10n.pairDevice) { showPairing = true }
                    .controlSize(.large)
            }
            .padding(12).frame(maxWidth: .infinity)
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
