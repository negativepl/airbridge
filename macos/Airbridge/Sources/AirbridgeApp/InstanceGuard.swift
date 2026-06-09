import Foundation
import AppKit

/// Zapobiega uruchomieniu drugiej instancji AirBridge.
///
/// Problem: kliknięcie powiadomienia każe LaunchServices „ponownie otworzyć"
/// apkę dla `com.airbridge.macos`. Gdy pod tym samym bundle ID zarejestrowanych
/// jest kilka kopii (np. stara `/Applications` + martwe wpisy po DMG), LaunchServices
/// potrafi wystartować *drugi* proces zamiast aktywować działający. Drugi proces
/// próbuje zbindować port 8765 → `NWError 48 Address already in use` → błędny toast.
///
/// Rozwiązanie: zanim cokolwiek dotknie portu, sprawdzamy czy działa już inna
/// instancja. Jeśli tak — aktywujemy ją i kończymy bieżący proces.
enum InstanceGuard {

    /// Czysta (testowalna) decyzja: czy działa inna instancja `bundleId` poza `selfPID`?
    /// Zwraca PID istniejącej instancji do aktywacji albo `nil`.
    static func otherInstancePID(
        bundleId: String,
        selfPID: Int32,
        running: [(bundleId: String?, pid: Int32)]
    ) -> Int32? {
        running.first { $0.bundleId == bundleId && $0.pid != selfPID }?.pid
    }

    /// Jeśli inna instancja AirBridge już działa: aktywuje ją i kończy bieżący proces.
    /// Musi być wywołane jako pierwsza rzecz przy starcie, ZANIM wystartują serwery.
    static func terminateIfAlreadyRunning() {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.airbridge.macos"
        let running = NSWorkspace.shared.runningApplications.map {
            (bundleId: $0.bundleIdentifier, pid: $0.processIdentifier)
        }

        guard let otherPID = otherInstancePID(bundleId: bundleId, selfPID: selfPID, running: running) else {
            return
        }

        // Przekaż fokus już działającej instancji, żeby klik użytkownika coś robił.
        NSRunningApplication(processIdentifier: otherPID)?.activate()
        exit(0)
    }
}
