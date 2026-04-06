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

    private var isDisconnected: Bool {
        viewModel?.statusMessage.contains("Rozłączono") == true || viewModel?.statusMessage.contains("Disconnected") == true
    }

    private func connectionCard(_ vm: HomeViewModel) -> some View {
        HStack(spacing: 14) {
            Group {
                if vm.isConnected {
                    Circle().fill(.green).frame(width: 12, height: 12)
                        .shadow(color: .green.opacity(0.6), radius: 6)
                        .shadow(color: .green.opacity(0.3), radius: 12)
                } else if !vm.hasPairedDevices {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                } else if isDisconnected {
                    Circle().fill(.gray).frame(width: 12, height: 12)
                } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Failed") || vm.statusMessage.contains("Błąd") {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 28, height: 28)
            .animation(.easeInOut(duration: 0.3), value: vm.isConnected)
            .animation(.easeInOut(duration: 0.3), value: vm.statusMessage)

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
                .animation(.easeInOut(duration: 0.3), value: vm.isConnected)

                Group {
                    if vm.isConnected, let ip = vm.localIP {
                        Text(ip)
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
            if vm.isConnected {
                Button(L10n.disconnect) {
                    vm.disconnect()
                }
                .controlSize(.large)
            } else if isDisconnected {
                Button(L10n.reconnect) {
                    vm.reconnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if !vm.hasPairedDevices {
                Button(L10n.pairDevice) {
                    showPairing = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Błąd") {
                Button(L10n.reconnect) {
                    vm.reconnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func transferCard(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.fileTransfer, systemImage: "arrow.down.circle")
                .font(.system(size: 14)).fontWeight(.semibold)
            Text(vm.transferFileName)
                .font(.system(size: 14)).lineLimit(1)
            ProgressView(value: vm.transferProgress)
            HStack {
                Text(formatSpeed(vm.transferSpeed))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(formatEta(vm.transferEta))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func recentActivityCard(_ vm: HomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.isPL ? "Ostatnia aktywność" : "Recent Activity", systemImage: "clock")
                .font(.system(size: 14)).fontWeight(.semibold)
                .padding(.bottom, 4)

            let items = vm.recentActivity
            if items.isEmpty {
                Text(L10n.isPL ? "Brak aktywności" : "No activity yet")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                ForEach(items) { record in
                    HStack(spacing: 8) {
                        Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc")
                            .foregroundStyle(record.direction == .sent ? Color.primary : Color.accentColor)
                        Text(record.description).font(.system(size: 14)).lineLimit(1)
                        Spacer()
                        Text(record.timestamp, style: .relative)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var noPairedDevicesCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 36)).foregroundStyle(.secondary)
            Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            Button(L10n.pairDevice) {
                showPairing = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 16))
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
