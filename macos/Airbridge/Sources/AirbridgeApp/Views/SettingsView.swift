import SwiftUI
import ServiceManagement
import AirbridgeSecurity

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService

    @State private var viewModel: SettingsViewModel?
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/Airbridge"
    @State private var showPairing = false
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay: String = GlobalHotkeyService.currentShortcutDisplay()
    @State private var shortcutMonitor: Any?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let vm = viewModel {
                    // Paired devices
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.isPL ? "Sparowane urządzenia" : "Paired Devices", systemImage: "iphone")
                            .font(.system(size: 15, weight: .semibold))

                        if vm.pairedDevices.isEmpty {
                            Text(L10n.noDevicePaired)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.pairedDevices, id: \.publicKeyBase64) { device in
                                HStack(spacing: 12) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.deviceName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.pairedAt, style: .date)
                                            .font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L10n.isPL ? "Usuń" : "Remove", role: .destructive) {
                                        vm.unpairDevice(publicKey: device.publicKeyBase64)
                                    }
                                    .controlSize(.large)
                                }
                            }
                        }

                        Button(L10n.isPL ? "Dodaj nowe urządzenie" : "Add New Device") {
                            showPairing = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))

                    // General
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.general, systemImage: "gearshape")
                            .font(.system(size: 15, weight: .semibold))

                        Toggle(L10n.launchAtLogin, isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                launchAtLogin = newValue
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    launchAtLogin = !newValue
                                }
                            }
                        ))
                        .font(.system(size: 14))

                        Toggle(L10n.isPL ? "Dźwięk po odebraniu" : "Sound on receive", isOn: $playSound)
                            .font(.system(size: 14))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))

                    // Quick Drop shortcut
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.quickDropShortcut, systemImage: "keyboard")
                            .font(.system(size: 15, weight: .semibold))

                        HStack {
                            Text(L10n.quickDropShortcut)
                                .font(.system(size: 14))
                            Spacer()

                            if isRecordingShortcut {
                                Text(L10n.pressNewShortcut)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.orange)
                                    .onAppear { startRecordingShortcut() }
                            } else {
                                Text(shortcutDisplay)
                                    .font(.system(size: 14, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            Button(isRecordingShortcut
                                ? (L10n.isPL ? "Anuluj" : "Cancel")
                                : (L10n.isPL ? "Zmień" : "Change")
                            ) {
                                isRecordingShortcut.toggle()
                                if !isRecordingShortcut { stopRecordingShortcut() }
                            }
                            .controlSize(.large)

                            if UserDefaults.standard.integer(forKey: "dropZoneShortcutKeyCode") != 0 {
                                Button(L10n.resetToDefault) {
                                    UserDefaults.standard.removeObject(forKey: "dropZoneShortcutKeyCode")
                                    UserDefaults.standard.removeObject(forKey: "dropZoneShortcutModifiers")
                                    shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
                                }
                                .controlSize(.large)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))

                    // File transfer
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.fileTransfer, systemImage: "folder")
                            .font(.system(size: 15, weight: .semibold))

                        HStack {
                            Text(L10n.downloadFolder)
                                .font(.system(size: 14))
                            Spacer()
                            Text(downloadFolder)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button(L10n.change) { chooseDownloadFolder() }
                                .controlSize(.large)
                        }

                        Text(L10n.receivedFilesSaved)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))

                    // Connection status
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.connection, systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .semibold))

                        HStack {
                            Text(L10n.status)
                                .font(.system(size: 14))
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(vm.isConnected ? Color.green : Color.orange)
                                    .frame(width: 10, height: 10)
                                Text(vm.isConnected ? L10n.connected : L10n.notConnected)
                                    .font(.system(size: 14))
                            }
                        }

                        if let ip = vm.localIP {
                            HStack {
                                Text(L10n.localIP)
                                    .font(.system(size: 14))
                                Spacer()
                                Text(ip)
                                    .font(.system(size: 14))
                                    .textSelection(.enabled)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(
                    connectionService: connectionService,
                    pairingService: pairingService
                )
            }
            pairingService.refreshPairedDevices()
        }
        .onChange(of: connectionService.isConnected) { _, _ in
            pairingService.refreshPairedDevices()
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

    private func startRecordingShortcut() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command) || modifiers.contains(.control) else {
                return event // Require at least Cmd or Ctrl
            }
            UserDefaults.standard.set(Int(event.keyCode), forKey: "dropZoneShortcutKeyCode")
            UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "dropZoneShortcutModifiers")
            shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
            isRecordingShortcut = false
            stopRecordingShortcut()
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }
}
