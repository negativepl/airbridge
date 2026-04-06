import AppKit
import Carbon.HIToolbox

@Observable
@MainActor
final class GlobalHotkeyService {

    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private weak var connectionService: ConnectionService?
    @ObservationIgnored private weak var fileTransferService: FileTransferService?

    // Default: Cmd + Shift + D
    @ObservationIgnored private let defaultKeyCode: UInt16 = 2 // 'd' key
    @ObservationIgnored private let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    func start() {
        stop()

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
        guard let connectionService, let fileTransferService else { return }
        DropZonePopup.shared.toggle(
            connectionService: connectionService,
            fileTransferService: fileTransferService
        )
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
}
