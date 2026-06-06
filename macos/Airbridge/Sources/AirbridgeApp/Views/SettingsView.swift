import SwiftUI
import ServiceManagement
import AirbridgeSecurity

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService
    let hotkeyService: GlobalHotkeyService
    let notificationService: NotificationService

    @State private var viewModel: SettingsViewModel
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/AirBridge"
    @State private var showPairing = false
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay: String = GlobalHotkeyService.currentShortcutDisplay()
    @State private var shortcutMonitor: Any?
    @State private var accessibilityPollTimer: Timer?

    init(connectionService: ConnectionService, pairingService: PairingService, hotkeyService: GlobalHotkeyService, notificationService: NotificationService) {
        self.connectionService = connectionService
        self.pairingService = pairingService
        self.hotkeyService = hotkeyService
        self.notificationService = notificationService
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
            notificationsSection
            quickDropSection
            fileTransferSection
        }
        .onAppear {
            pairingService.refreshPairedDevices()
            accessibilityGranted = AXIsProcessTrusted()
            if !accessibilityGranted {
                startAccessibilityPolling()
            }
        }
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
        .onChange(of: connectionService.isConnected) { _, _ in
            pairingService.refreshPairedDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let granted = AXIsProcessTrusted()
            accessibilityGranted = granted
            if granted {
                accessibilityPollTimer?.invalidate()
                accessibilityPollTimer = nil
                hotkeyService.start()
            }
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
                HStack(spacing: 12) {
                    Text(L10n.noDevicePaired)
                        .font(.ab(.body))
                        .foregroundStyle(.secondary)
                    Spacer()
                    addDeviceButton
                }
            } else {
                ForEach(Array(vm.pairedDevices.enumerated()), id: \.element.publicKeyBase64) { index, device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.ab(.title3))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.deviceName)
                                .font(.ab(.body, weight: .medium))
                            Text(device.pairedAt, style: .date)
                                .font(.ab(.footnote))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // "Add" sits next to the last device's "Remove".
                        if index == vm.pairedDevices.count - 1 {
                            addDeviceButton
                        }
                        Button(L10n.isPL ? "Usuń" : "Remove", role: .destructive) {
                            vm.unpairDevice(publicKey: device.publicKeyBase64)
                        }
                        .controlSize(.extraLarge)
                    }
                }
            }
        }
    }

    private var addDeviceButton: some View {
        Button(L10n.isPL ? "Dodaj nowe urządzenie" : "Add New Device") {
            showPairing = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
    }

    private var notificationsSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.isPL ? "Powiadomienia" : "Notifications"), systemImage: "bell.badge") {
            Toggle(L10n.isPL ? "Pokazuj powiadomienia z telefonu" : "Show phone notifications", isOn: Binding(
                get: { notificationService.enabled },
                set: { notificationService.setEnabled($0) }
            ))
            .font(.ab(.body))

            if notificationService.knownApps.isEmpty {
                Text(L10n.isPL ? "Powiadomienia pojawią się tu, gdy telefon je przyśle."
                               : "Apps will appear here once the phone sends notifications.")
                    .font(.ab(.subheadline)).foregroundStyle(.secondary)
            } else {
                ForEach(notificationService.knownApps.sorted { $0.value < $1.value }, id: \.key) { pkg, name in
                    Toggle(name, isOn: Binding(
                        get: { !notificationService.disabledApps.contains(pkg) },
                        set: { notificationService.setAppEnabled(pkg, $0) }
                    ))
                    .font(.ab(.body))
                    .disabled(!notificationService.enabled)
                }
            }
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
            .font(.ab(.body))

            Toggle(L10n.isPL ? "Dźwięk po odebraniu" : "Sound on receive", isOn: $playSound)
                .font(.ab(.body))

            Toggle(L10n.isPL ? "Pokaż w Docku" : "Show in Dock", isOn: Binding(
                get: { showInDock },
                set: { newValue in
                    showInDock = newValue
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            ))
            .font(.ab(.body))
        }
    }

    private var quickDropSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.quickDropShortcut), systemImage: "keyboard") {
            HStack {
                Text(L10n.isPL ? "Dostępność:" : "Accessibility:")
                    .font(.ab(.body))
                Spacer()
                HStack(spacing: 6) {
                    StatusIndicator(state: accessibilityGranted ? .connected : .error, size: 12)
                    Text(accessibilityGranted
                        ? (L10n.isPL ? "Nadane" : "Granted")
                        : (L10n.isPL ? "Brak uprawnień" : "Not granted"))
                        .font(.ab(.body))
                }
                if !accessibilityGranted {
                    Button(L10n.isPL ? "Nadaj" : "Grant") {
                        hotkeyService.requestAccessibilityAndStart()
                        startAccessibilityPolling()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                }
            }

            Text(L10n.isPL
                ? "Skrót działa globalnie tylko z uprawnieniami Dostępności."
                : "The shortcut works globally only with Accessibility permission.")
                .font(.ab(.footnote))
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(L10n.isPL ? "Skrót:" : "Shortcut:")
                    .font(.ab(.body))
                Spacer()

                if isRecordingShortcut {
                    Text(L10n.pressNewShortcut)
                        .font(.ab(.body))
                        .foregroundStyle(.orange)
                        .onAppear { startRecordingShortcut() }
                } else {
                    Text(shortcutDisplay)
                        .font(.ab(.body, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }

                Button(isRecordingShortcut
                    ? (L10n.isPL ? "Anuluj" : "Cancel")
                    : L10n.change
                ) {
                    isRecordingShortcut.toggle()
                    if !isRecordingShortcut { stopRecordingShortcut() }
                }
                .controlSize(.extraLarge)

                if UserDefaults.standard.integer(forKey: "dropZoneShortcutKeyCode") != 0 {
                    Button(L10n.resetToDefault) {
                        UserDefaults.standard.removeObject(forKey: "dropZoneShortcutKeyCode")
                        UserDefaults.standard.removeObject(forKey: "dropZoneShortcutModifiers")
                        shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
                    }
                    .controlSize(.extraLarge)
                }
            }
        }
    }

    private var fileTransferSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "folder") {
            HStack {
                Text(L10n.downloadFolder)
                    .font(.ab(.body))
                Spacer()
                Text(downloadFolder)
                    .font(.ab(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(L10n.change) { chooseDownloadFolder() }
                    .controlSize(.extraLarge)
            }

            Text(L10n.receivedFilesSaved)
                .font(.ab(.footnote))
                .foregroundStyle(.secondary)
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
