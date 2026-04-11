import SwiftUI
import ServiceManagement
import AirbridgeSecurity

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService
    let hotkeyService: GlobalHotkeyService

    @State private var viewModel: SettingsViewModel
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/AirBridge"
    @State private var showPairing = false
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay: String = GlobalHotkeyService.currentShortcutDisplay()
    @State private var shortcutMonitor: Any?
    @State private var accessibilityPollTimer: Timer?

    init(connectionService: ConnectionService, pairingService: PairingService, hotkeyService: GlobalHotkeyService) {
        self.connectionService = connectionService
        self.pairingService = pairingService
        self.hotkeyService = hotkeyService
        self._viewModel = State(initialValue: SettingsViewModel(
            connectionService: connectionService,
            pairingService: pairingService
        ))
    }

    var body: some View {
        let vm = viewModel
        VStack(spacing: 16) {
            pairedDevicesSection(vm)
            generalSection
            quickDropSection
            fileTransferSection
            connectionSection(vm)
        }
        .onAppear {
            pairingService.refreshPairedDevices()
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
        .onChange(of: connectionService.isConnected) { _, _ in
            pairingService.refreshPairedDevices()
        }
        .sheet(isPresented: $showPairing) {
            PairingView(pairingService: pairingService, connectionService: connectionService, isPresented: $showPairing)
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let granted = AXIsProcessTrusted()
            DispatchQueue.main.async {
                accessibilityGranted = granted
                if granted {
                    accessibilityPollTimer?.invalidate()
                    accessibilityPollTimer = nil
                }
            }
        }
    }

    private func pairedDevicesSection(_ vm: SettingsViewModel) -> some View {
        GlassSection(
            title: LocalizedStringKey(L10n.isPL ? "Sparowane urządzenia" : "Paired Devices"),
            systemImage: "iphone"
        ) {
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
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
    }

    private var generalSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.general), systemImage: "gearshape") {
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
    }

    private var quickDropSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.quickDropShortcut), systemImage: "keyboard") {
            HStack {
                Text(L10n.isPL ? "Dostępność:" : "Accessibility:")
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 6) {
                    StatusIndicator(state: accessibilityGranted ? .connected : .error, size: 12)
                    Text(accessibilityGranted
                        ? (L10n.isPL ? "Nadane" : "Granted")
                        : (L10n.isPL ? "Brak uprawnień" : "Not granted"))
                        .font(.system(size: 14))
                }
                if !accessibilityGranted {
                    Button(L10n.isPL ? "Nadaj" : "Grant") {
                        hotkeyService.requestAccessibilityAndStart()
                        startAccessibilityPolling()
                    }
                    .controlSize(.large)
                }
            }

            Text(L10n.isPL
                ? "Skrót działa globalnie tylko z uprawnieniami Dostępności."
                : "The shortcut works globally only with Accessibility permission.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(L10n.isPL ? "Skrót:" : "Shortcut:")
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
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
    }

    private var fileTransferSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "folder") {
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func connectionSection(_ vm: SettingsViewModel) -> some View {
        GlassSection(title: LocalizedStringKey(L10n.connection), systemImage: "antenna.radiowaves.left.and.right") {
            HStack {
                Text(L10n.status)
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 6) {
                    StatusIndicator(state: vm.isConnected ? .connected : .disconnected, size: 12)
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
                        .contentTransition(.numericText())
                }
            }
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
                return event
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
