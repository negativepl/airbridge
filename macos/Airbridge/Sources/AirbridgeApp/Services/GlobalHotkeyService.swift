import AppKit
import Carbon.HIToolbox

@Observable
@MainActor
final class GlobalHotkeyService {

    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private weak var fileTransferService: FileTransferService?

    // Default: Ctrl + Option + Cmd + A (Airbridge) — triple-modifier combo to
    // avoid any collision with macOS system shortcuts or common app shortcuts.
    @ObservationIgnored private let defaultKeyCode: UInt16 = 0 // 'a' key
    @ObservationIgnored private let defaultModifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let key = "AXTrustedCheckOptionPrompt" as CFString
            let options = [key: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    /// Silent start — registers global hotkey only if Accessibility is already granted.
    /// Does NOT show any TCC prompt. The user must explicitly request access from
    /// Settings → Quick Drop → "Grant" button. After granting, the app registers
    /// the monitors the next time start() is called (e.g. on relaunch, or when the
    /// user explicitly calls requestAccessibilityAndStart()).
    func start() {
        stop()
        guard AXIsProcessTrusted() else { return }
        registerMonitors()
    }

    /// Explicitly request Accessibility permission and start the hotkey once granted.
    /// Shows the system TCC prompt. Intended to be called from a user action in Settings.
    func requestAccessibilityAndStart() {
        if AXIsProcessTrusted() {
            start()
            return
        }
        requestAccessibilityIfNeeded()
        pollForAccessibility()
    }

    private func pollForAccessibility() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                t.invalidate()
                DispatchQueue.main.async {
                    self?.registerMonitors()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func registerMonitors() {
        // Global monitor — fires when app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }

        // Local monitor — fires when app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            // Check synchronously if this is our shortcut — consume the event
            if self?.matchesShortcut(event) == true {
                return nil
            }
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard matchesShortcut(event) else { return }
        TransferPopup.shared.toggle()
    }

    func matchesShortcut(_ event: NSEvent) -> Bool {
        let defaults = UserDefaults.standard
        let keyCode = UInt16(defaults.integer(forKey: "dropZoneShortcutKeyCode"))
        let modifierRaw = defaults.integer(forKey: "dropZoneShortcutModifiers")

        let targetKeyCode = keyCode != 0 ? keyCode : defaultKeyCode
        let targetModifiers = modifierRaw != 0
            ? NSEvent.ModifierFlags(rawValue: UInt(modifierRaw))
            : defaultModifiers

        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == targetKeyCode && eventModifiers == targetModifiers
    }

    static func currentShortcutDisplay() -> String {
        let defaults = UserDefaults.standard
        let keyCode = UInt16(defaults.integer(forKey: "dropZoneShortcutKeyCode"))
        let modifierRaw = defaults.integer(forKey: "dropZoneShortcutModifiers")

        if keyCode == 0 && modifierRaw == 0 {
            return "⌃⌥⌘A"
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifierRaw))
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyString = keyCodeToString(keyCode)
        parts.append(keyString)
        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return String(format: "0x%02X", keyCode)
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        layoutData.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard length > 0 else { return String(format: "0x%02X", keyCode) }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
