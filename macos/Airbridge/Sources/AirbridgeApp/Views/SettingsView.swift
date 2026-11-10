import SwiftUI
import AirbridgeSecurity
import Protocol

struct SettingsView: View {
    @AppStorage(DiagnosticsUnlock.key) private var diagnosticsUnlocked = false
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
    @AppStorage("clipboardReceipt") private var clipboardReceipt = true
    @AppStorage(BrowserPicker.preferenceKey) private var linkBrowser = BrowserPicker.inUse
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage(ConnectionService.showIncomingCallsKey) private var showIncomingCalls = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/AirBridge"
    @State private var showPairing = false
    @State private var showNotificationApps = false
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
        // System Settings' layout: a grouped form, a section per topic with
        // its explanation in the footer, standard controls.
        Form {
            pairedDevicesSection(vm)
            generalSection
            headphoneSection
            notificationsSection
            quickDropSection
            fileTransferSection
            if diagnosticsUnlocked {
                diagnosticsSection
            }
            AboutSection(updateService: updateService, phoneAppVersion: connectionService.deviceInfo?.appVersion)
        }
        .formStyle(.grouped)
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
        .onChange(of: connectionService.pairingRevision) { _, _ in
            pairingService.refreshPairedDevices()
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
        .sheet(isPresented: $showNotificationApps) {
            NotificationAppsSheet(notificationService: notificationService)
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
        Section {
            if vm.pairedDevices.isEmpty {
                Text(L10n.noDevicePaired).foregroundStyle(.secondary)
            } else {
                ForEach(vm.pairedDevices, id: \.publicKeyBase64) { device in
                    LabeledContent {
                        Button(L10n.isPL ? "Usuń…" : "Remove…", role: .destructive) {
                            vm.unpairDevice(publicKey: device.publicKeyBase64)
                        }
                    } label: {
                        Label {
                            Text(device.deviceName)
                            Text(L10n.isPL ? "Sparowano \(device.pairedAt.formatted(date: .long, time: .omitted))"
                                           : "Paired \(device.pairedAt.formatted(date: .long, time: .omitted))")
                        } icon: {
                            Image(systemName: "smartphone")
                        }
                    }
                }
            }
        } header: {
            Text(L10n.isPL ? "Sparowane urządzenia" : "Paired Devices")
        } footer: {
            HStack {
                Spacer()
                Button(L10n.isPL ? "Dodaj urządzenie…" : "Add Device…") { showPairing = true }
            }
        }
    }

    private var notificationsSection: some View {
        Section {
            Toggle(L10n.isPL ? "Pokazuj powiadomienia z telefonu" : "Show notifications from the phone", isOn: Binding(
                get: { notificationService.enabled },
                set: { notificationService.setEnabled($0) }
            ))
            Toggle(isOn: $showIncomingCalls) {
                Text(L10n.isPL ? "Pokazuj połączenia przychodzące" : "Show incoming calls")
                Text(L10n.isPL ? "Wyspa z rozmówcą oraz przyciskami Odbierz i Odrzuć, gdy telefon dzwoni."
                               : "An island with the caller and Answer and Decline buttons while the phone rings.")
            }
            if !notificationService.knownApps.isEmpty {
                // The apps live in their own sheet. As rows of this form, which
                // is not lazy, some eighty switches were laid out again on
                // every step of a scroll, and the whole page scrolled slowly.
                LabeledContent {
                    Button(L10n.isPL ? "Wybierz…" : "Choose…") { showNotificationApps = true }
                        .disabled(!notificationService.enabled)
                } label: {
                    Text(L10n.isPL ? "Aplikacje" : "Apps")
                    Text(notificationAppsSummary)
                }
            }
        } header: {
            Text(L10n.isPL ? "Powiadomienia" : "Notifications")
        } footer: {
            Text(notificationService.knownApps.isEmpty
                 ? (L10n.isPL ? "Aplikacje pojawią się tutaj, gdy telefon przyśle od nich powiadomienia."
                              : "Apps appear here once the phone sends their notifications.")
                 : (L10n.isPL ? "Powiadomienia pojawiają się na bieżąco, gdy telefon je otrzymuje."
                              : "Notifications appear live, as the phone receives them."))
                .foregroundStyle(.secondary)
        }
    }

    /// "Włączone: 62 z 80", counted over the apps the phones have reported.
    private var notificationAppsSummary: String {
        let known = notificationService.knownApps.keys
        let on = known.filter { !notificationService.disabledApps.contains($0) }.count
        return L10n.isPL ? "Włączone: \(on) z \(known.count)" : "\(on) of \(known.count) on"
    }

    /// An app icon at menu size; NSWorkspace hands it out at 32 pt.
    private static func menuIcon(for appURL: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private var generalSection: some View {
        Section {
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
            Toggle(L10n.isPL ? "Dźwięk po odebraniu" : "Sound on receive", isOn: $playSound)
            Toggle(L10n.clipboardReceiptSetting, isOn: $clipboardReceipt)
            Picker(L10n.linkBrowserSetting, selection: $linkBrowser) {
                Text(L10n.linkBrowserInUse).tag(BrowserPicker.inUse)
                Text(L10n.linkBrowserSystemDefault).tag(BrowserPicker.systemDefault)
                Divider()
                ForEach(BrowserPicker.installedBrowsers()) { browser in
                    Label {
                        Text(browser.name)
                    } icon: {
                        Image(nsImage: Self.menuIcon(for: browser.url))
                    }
                    .tag(browser.id)
                }
            }
            Toggle(L10n.isPL ? "Pokaż w Docku" : "Show in Dock", isOn: Binding(
                get: { showInDock },
                set: { newValue in
                    showInDock = newValue
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            ))
        } header: {
            Text(L10n.general)
        } footer: {
            if let launchAtLoginError {
                Text(L10n.isPL ? "Nie udało się ustawić autostartu: \(launchAtLoginError)"
                               : "Couldn't set launch at login: \(launchAtLoginError)")
                    .foregroundStyle(.red)
            }
        }
    }

    private var headphoneSection: some View {
        Section {
            Toggle(L10n.isPL ? "Przełączanie słuchawek" : "Headphone handoff", isOn: Binding(
                get: { bluetoothAudio.enabled },
                set: { bluetoothAudio.enabled = $0 }
            ))
            if bluetoothAudio.enabled {
                Picker(L10n.isPL ? "Słuchawki" : "Headphones", selection: Binding(
                    get: { bluetoothAudio.selectedAddress ?? "" },
                    set: { address in
                        bluetoothAudio.selectedAddress = address.isEmpty ? nil : address
                        bluetoothAudio.selectedName =
                            pairedAudio.first(where: { $0.address == address })?.name
                    }
                )) {
                    Text(L10n.isPL ? "Nie wybrano" : "Not Selected").tag("")
                    ForEach(pairedAudio) { device in
                        Text(device.name).tag(device.address)
                    }
                }
                Toggle(L10n.isPL ? "Proponuj przełączanie" : "Suggest switching", isOn: Binding(
                    get: { bluetoothAudio.autoSwitchEnabled },
                    set: { bluetoothAudio.autoSwitchEnabled = $0 }
                ))
            }
        } header: {
            Text(L10n.isPL ? "Słuchawki (beta)" : "Headphones (beta)")
        } footer: {
            Text(bluetoothAudio.enabled
                 ? (L10n.isPL ? "Słuchawki muszą być sparowane z tym Makiem i z telefonem. Proponowanie przełączania pyta przed przeniesieniem słuchawek na urządzenie, które zaczyna odtwarzać."
                              : "The headphones must be paired with this Mac and the phone. Suggest switching asks before moving them to the device that starts playing.")
                 : (L10n.isPL ? "Przenosi słuchawki Bluetooth między telefonem a tym Makiem."
                              : "Moves Bluetooth headphones between the phone and this Mac."))
                .foregroundStyle(.secondary)
        }
        .task { pairedAudio = await BluetoothAudioService.pairedAudioDevices() }
    }

    private var quickDropSection: some View {
        Section {
            LabeledContent(L10n.isPL ? "Dostęp do Dostępności" : "Accessibility Access") {
                HStack(spacing: 10) {
                    Label {
                        Text(accessibilityGranted ? (L10n.isPL ? "Nadany" : "Granted")
                                                  : (L10n.isPL ? "Nie nadano" : "Not Granted"))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(accessibilityGranted ? .green : .red)
                    }
                    if !accessibilityGranted && accessibilityAwaitingRestart {
                        // AXIsProcessTrusted() is cached per-process — a freshly granted
                        // Accessibility permission only applies after a relaunch.
                        Button(L10n.isPL ? "Uruchom ponownie" : "Relaunch") { AppRelauncher.relaunch() }
                    } else if !accessibilityGranted {
                        Button(L10n.isPL ? "Nadaj…" : "Grant…") {
                            hotkeyService.requestAccessibilityAndStart()
                            accessibilityAwaitingRestart = true
                            startAccessibilityPolling()
                        }
                    }
                }
            }
            LabeledContent(L10n.isPL ? "Skrót" : "Shortcut") {
                HStack(spacing: 10) {
                    if isRecordingShortcut {
                        Text(L10n.pressNewShortcut)
                            .foregroundStyle(.secondary)
                            .onAppear { startRecordingShortcut() }
                    } else {
                        Text(shortcutDisplay).monospaced()
                    }
                    Button(isRecordingShortcut ? (L10n.isPL ? "Anuluj" : "Cancel") : L10n.change) {
                        isRecordingShortcut.toggle()
                        if !isRecordingShortcut { stopRecordingShortcut() }
                    }
                    if UserDefaults.standard.integer(forKey: "dropZoneShortcutKeyCode") != 0 {
                        Button(L10n.resetToDefault) {
                            UserDefaults.standard.removeObject(forKey: "dropZoneShortcutKeyCode")
                            UserDefaults.standard.removeObject(forKey: "dropZoneShortcutModifiers")
                            shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
                        }
                    }
                }
            }
        } header: {
            Text(L10n.quickDropShortcut)
        } footer: {
            Text(L10n.isPL ? "Skrót działa w całym systemie tylko z dostępem do Dostępności."
                           : "The shortcut works system-wide only with Accessibility access.")
                .foregroundStyle(.secondary)
        }
    }

    private var fileTransferSection: some View {
        Section {
            LabeledContent(L10n.isPL ? "Folder pobierania" : "Download Folder") {
                HStack(spacing: 10) {
                    Text(downloadFolder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L10n.change) { chooseDownloadFolder() }
                }
            }
        } header: {
            Text(L10n.fileTransfer)
        } footer: {
            Text(L10n.receivedFilesSaved).foregroundStyle(.secondary)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            LabeledContent(L10n.isPL ? "Raport diagnostyczny" : "Diagnostic Report") {
                Button(L10n.isPL ? "Zapisz…" : "Save…") { saveDiagnosticReport() }
            }
            LabeledContent(L10n.isPL ? "Sekcja diagnostyki" : "Diagnostics Section") {
                Button(L10n.isPL ? "Ukryj" : "Hide") { diagnosticsUnlocked = false }
            }
        } header: {
            Text(L10n.isPL ? "Diagnostyka" : "Diagnostics")
        } footer: {
            Text(L10n.isPL
                 ? "Raport to plik tekstowy z wersją aplikacji, stanem połączenia i ostatnimi wpisami dziennika. Zostaje na tym Macu i nie jest nigdzie wysyłany. Aby przywrócić ukrytą sekcję, kliknij siedem razy numer wersji w sekcji O aplikacji."
                 : "The report is a text file with the app version, connection state and recent log entries. It stays on this Mac and is not uploaded. To bring the hidden section back, click the version number in About seven times.")
                .foregroundStyle(.secondary)
        }
    }

    private func saveDiagnosticReport() {
        let report = DiagnosticReportService.makeReport(connectionService: connectionService)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DiagnosticReport.suggestedFileName()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? report.write(to: url, atomically: true, encoding: .utf8)
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

/// The apps whose notifications the phones have sent, each with its switch,
/// laid out like an app list in System Settings › Privacy & Security: a title
/// and explanation, a search field, a bordered list with the switch at the
/// trailing edge and Done underneath. A `List`, so rows are created as they
/// scroll into view.
private struct NotificationAppsSheet: View {
    let notificationService: NotificationService

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var apps: [(package: String, name: String)] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return notificationService.knownApps
            .map { (package: $0.key, name: $0.value) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Powiadomienia aplikacji" : "App Notifications")
                    .font(.headline)
                Text(L10n.isPL ? "Wybierz aplikacje, których powiadomienia z telefonu mają być pokazywane na tym Macu."
                               : "Choose the apps whose notifications from the phone are shown on this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SearchField(text: $searchText, prompt: L10n.isPL ? "Szukaj" : "Search")

            List(apps, id: \.package) { app in
                LabeledContent(app.name) {
                    Toggle(app.name, isOn: Binding(
                        get: { !notificationService.disabledApps.contains(app.package) },
                        set: { notificationService.setAppEnabled(app.package, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            // The box of a grouped form section, as on the Settings page
            // behind the sheet: the system's fill, rounded, rows parted by
            // separators. The bordered list style is a square-cornered table.
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10, style: .continuous))
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            .overlay {
                if apps.isEmpty { ContentUnavailableView.search(text: searchText) }
            }

            HStack {
                Spacer()
                Button(L10n.isPL ? "Gotowe" : "Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 560)
    }
}

/// AppKit's search field. `.searchable` needs a toolbar to live in, and in a
/// sheet that toolbar is a bar of its own with the field alone in a corner.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
