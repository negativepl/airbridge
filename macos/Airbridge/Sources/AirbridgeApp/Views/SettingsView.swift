import SwiftUI
import AirbridgeSecurity

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService

    @State private var viewModel: SettingsViewModel?
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/Airbridge"
    @State private var showPairing = false

    var body: some View {
        Form {
            if let vm = viewModel {
                Section(L10n.isPL ? "Sparowane urządzenia" : "Paired Devices") {
                    if vm.pairedDevices.isEmpty {
                        Text(L10n.noDevicePaired).foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.pairedDevices, id: \.publicKeyBase64) { device in
                            HStack {
                                Image(systemName: "iphone")
                                VStack(alignment: .leading) {
                                    Text(device.deviceName)
                                    Text(device.pairedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L10n.isPL ? "Usuń" : "Remove", role: .destructive) {
                                    vm.unpairDevice(publicKey: device.publicKeyBase64)
                                }
                            }
                        }
                    }
                    Button { showPairing = true } label: {
                        Label(L10n.isPL ? "Dodaj nowe urządzenie" : "Add New Device", systemImage: "plus")
                    }
                }
                Section(L10n.general) {
                    Toggle(L10n.launchAtLogin, isOn: $launchAtLogin)
                    Toggle(L10n.isPL ? "Dźwięk po odebraniu" : "Sound on receive", isOn: $playSound)
                }
                Section(L10n.fileTransfer) {
                    HStack {
                        Text(L10n.downloadFolder)
                        Spacer()
                        Text(downloadFolder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button(L10n.change) { chooseDownloadFolder() }
                    }
                    Text(L10n.receivedFilesSaved).font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.connection) {
                    LabeledContent(L10n.status) {
                        HStack(spacing: 6) {
                            Circle().fill(vm.isConnected ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text(vm.isConnected ? L10n.connected : L10n.notConnected)
                        }
                    }
                    if let ip = vm.localIP {
                        LabeledContent(L10n.localIP) { Text(ip).textSelection(.enabled) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(
                    connectionService: connectionService,
                    pairingService: pairingService
                )
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingView(pairingService: pairingService, connectionService: connectionService, isPresented: $showPairing)
        }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { downloadFolder = url.path }
    }
}
