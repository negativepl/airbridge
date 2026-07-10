import SwiftUI
import AirbridgeSecurity
import Protocol

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService
    let hotkeyService: GlobalHotkeyService
    let notificationService: NotificationService
    let updateService: UpdateService
    let bluetoothAudio: BluetoothAudioService

    @State private var viewModel: SettingsViewModel
    @State private var pairedAudio: [BluetoothAudioService.PairedAudioDevice] = []
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var accessibilityAwaitingRestart = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/AirBridge"
    @State private var showPairing = false
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay: String = GlobalHotkeyService.currentShortcutDisplay()
    @State private var shortcutMonitor: Any?
    @State private var accessibilityPollTimer: Timer?
    @State private var launchAtLoginError: String?

    init(connectionService: ConnectionService, pairingService: PairingService, hotkeyService: GlobalHotkeyService, notificationService: NotificationService, updateService: UpdateService, bluetoothAudio: BluetoothAudioService) {
        self.connectionService = connectionService
        self.pairingService = pairingService
        self.hotkeyService = hotkeyService
        self.notificationService = notificationService
        self.updateService = updateService
        self.bluetoothAudio = bluetoothAudio
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
            headphoneSection
            notificationsSection
            quickDropSection
            fileTransferSection
            updateSection
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
            // Leaving the view mid-recording must always remove the local
            // NSEvent monitor, or it would keep intercepting key events.
            isRecordingShortcut = false
            stopRecordingShortcut()
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
            Task { @MainActor in
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
                ForEach(vm.pairedDevices, id: \.publicKeyBase64) { device in
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
                        // Adding a device now lives in the window toolbar (next to
                        // the device switcher), so the row stays a clean list item.
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
        GlassSection {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: LocalizedStringKey(L10n.isPL ? "Powiadomienia" : "Notifications"),
                                  systemImage: "bell.badge")
                    Text(L10n.isPL ? "Powiadomienia pojawiają się na żywo, w miarę jak telefon je otrzymuje."
                                   : "Notifications appear live, as your phone receives them.")
                        .font(.ab(.subheadline)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { notificationService.enabled },
                    set: { notificationService.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

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
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = newValue
                        launchAtLoginError = nil
                    } catch {
                        // Nie udawaj, że działa: zostaw przełącznik w starym stanie
                        // (get zwróci niezmienione `launchAtLogin`) i pokaż powód.
                        launchAtLoginError = error.localizedDescription
                    }
                }
            ))
            .font(.ab(.body))

            if let launchAtLoginError {
                Text(L10n.isPL ? "Nie udało się ustawić autostartu: \(launchAtLoginError)"
                               : "Couldn't set launch at login: \(launchAtLoginError)")
                    .font(.ab(.caption))
                    .foregroundStyle(.red)
            }

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

    private var headphoneSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.isPL ? "Słuchawki (beta)" : "Headphones (beta)"),
                     systemImage: "headphones") {
            Toggle(L10n.isPL ? "Przełączanie słuchawek" : "Headphone handoff", isOn: Binding(
                get: { bluetoothAudio.enabled },
                set: { bluetoothAudio.enabled = $0 }
            ))
            .font(.ab(.body))

            if bluetoothAudio.enabled {
                Picker(L10n.isPL ? "Słuchawki:" : "Headphones:", selection: Binding(
                    get: { bluetoothAudio.selectedAddress ?? "" },
                    set: { address in
                        bluetoothAudio.selectedAddress = address.isEmpty ? nil : address
                        bluetoothAudio.selectedName =
                            pairedAudio.first(where: { $0.address == address })?.name
                    }
                )) {
                    Text(L10n.isPL ? "Nie wybrano" : "Not selected").tag("")
                    ForEach(pairedAudio) { device in
                        Text(device.name).tag(device.address)
                    }
                }
                .font(.ab(.body))

                Text(L10n.isPL
                    ? "Słuchawki muszą być sparowane zarówno z tym Makiem, jak i z telefonem."
                    : "The headphones must be paired with both this Mac and the phone.")
                    .font(.ab(.caption))
                    .foregroundStyle(.secondary)

                Toggle(L10n.isPL ? "Proponuj przełączanie" : "Suggest switching", isOn: Binding(
                    get: { bluetoothAudio.autoSwitchEnabled },
                    set: { bluetoothAudio.autoSwitchEnabled = $0 }
                ))
                .font(.ab(.body))
                Text(L10n.isPL ? "Pytaj przed przeniesieniem słuchawek na urządzenie, które zaczyna odtwarzać." : "Ask before moving the headphones to the device that starts playing.")
                    .font(.ab(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .task { pairedAudio = await BluetoothAudioService.pairedAudioDevices() }
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
                if !accessibilityGranted && accessibilityAwaitingRestart {
                    // AXIsProcessTrusted() is cached per-process — a freshly granted
                    // Accessibility permission only applies after a relaunch.
                    Button(L10n.isPL ? "Zrestartuj, aby zastosować" : "Restart to apply") {
                        AppRelauncher.relaunch()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                } else if !accessibilityGranted {
                    Button(L10n.isPL ? "Nadaj" : "Grant") {
                        hotkeyService.requestAccessibilityAndStart()
                        accessibilityAwaitingRestart = true
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

    private var updateSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.isPL ? "Aktualizacje" : "Updates"), systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 8) {
                updatePhaseContent
                if let mismatchedVersion {
                    Text(L10n.isPL
                         ? "Telefon ma wersję AirBridge \(mismatchedVersion). Zaktualizuj obie aplikacje, aby zachować zgodność."
                         : "Your phone runs AirBridge \(mismatchedVersion). Update both apps to keep them in sync.")
                        .font(.ab(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The phone's app version when it differs (ignoring a "-beta" suffix)
    /// from this Mac's own version — purely a comparison of versions already
    /// exchanged over the LAN, no update-server traffic involved.
    private var mismatchedVersion: String? {
        guard let remote = connectionService.deviceInfo?.appVersion, !remote.isEmpty else { return nil }
        let local = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !local.isEmpty, versionBase(remote) != versionBase(local) else { return nil }
        return remote
    }

    @ViewBuilder
    private var updatePhaseContent: some View {
        switch updateService.phase {
            case .idle:
                HStack {
                    Text(L10n.isPL ? "Sprawdź, czy dostępna jest nowsza wersja AirBridge."
                                   : "Check whether a newer version of AirBridge is available.")
                        .font(.ab(.body))
                        .foregroundStyle(.secondary)
                    Spacer()
                    checkButton
                }

            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.isPL ? "Sprawdzanie…" : "Checking…")
                        .font(.ab(.body))
                        .foregroundStyle(.secondary)
                }

            case .upToDate:
                HStack {
                    Label(L10n.isPL ? "Masz najnowszą wersję" : "You are on the latest version",
                          systemImage: "checkmark.circle.fill")
                        .font(.ab(.body))
                        .foregroundStyle(.green)
                    Spacer()
                    checkButton
                }

            case .available(let manifest):
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.isPL ? "Dostępna aktualizacja: \(manifest.version)"
                                           : "Update available: \(manifest.version)")
                                .font(.ab(.body, weight: .medium))
                            Text(L10n.isPL ? "Wydano \(manifest.publishedAt)" : "Released \(manifest.publishedAt)")
                                .font(.ab(.footnote))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.isPL ? "Zaktualizuj" : "Update") {
                            Task { await updateService.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                    }

                    let items = L10n.isPL ? manifest.changelog.pl : manifest.changelog.en
                    if !items.isEmpty {
                        Divider()
                        Text(L10n.isPL ? "Co nowego" : "What's new")
                            .font(.ab(.subheadline, weight: .semibold))
                        ForEach(items, id: \.self) { item in
                            Text("• \(item)")
                                .font(.ab(.body))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.isPL ? "Pobieranie…" : "Downloading…")
                        .font(.ab(.body))
                    ProgressView(value: progress)
                }

            case .installing:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.isPL ? "Instalowanie…" : "Installing…")
                        .font(.ab(.body))
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.isPL ? "Nie udało się sprawdzić aktualizacji" : "Could not check for updates")
                            .font(.ab(.body))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.isPL ? "Spróbuj ponownie" : "Retry") {
                            Task { await updateService.checkForUpdates() }
                        }
                        .controlSize(.extraLarge)
                    }
                    Text(message)
                        .font(.ab(.caption))
                        .foregroundStyle(.tertiary)
                }
            }
        }

    private var checkButton: some View {
        Button(L10n.isPL ? "Sprawdź aktualizacje" : "Check for updates") {
            Task { await updateService.checkForUpdates() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
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
