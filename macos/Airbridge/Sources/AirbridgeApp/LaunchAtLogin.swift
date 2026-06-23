import Foundation
import ServiceManagement
import os

/// Zarządza autostartem (login item) przez `SMAppService`.
///
/// Problem, który to naprawia: dotąd stan przełącznika żył wyłącznie w
/// `UserDefaults` (`@AppStorage("launchAtLogin")`), zupełnie niezależnie od tego,
/// czy macOS faktycznie ma zarejestrowany login item. A login item SMAppService
/// jest przypięty do podpisu/bundla aplikacji. Apka jest self-signed, więc
/// **cdhash zmienia się przy każdym buildzie**, a `dev-install.sh` podmienia
/// bundle w `/Applications` przy każdym wgraniu — przez co macOS unieważnia
/// starą rejestrację. UserDefaults dalej mówiło „ON", więc użytkownik widział
/// włączony autostart, a system nie odpalał nic. Do tego błąd `register()` był
/// połykany bez logu.
///
/// Rozwiązanie: traktujemy `UserDefaults` jako *intencję użytkownika*, a przy
/// każdym starcie uzgadniamy ją z realnym stanem systemu (`reconcileOnLaunch`).
/// Wszystko logujemy do `os.Logger` (widoczne w Console.app / `log stream`).
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.airbridge.macos", category: "LaunchAtLogin")
    private static let intentKey = "launchAtLogin"

    /// Intencja użytkownika (to, czego chce) — NIE to samo, co stan systemu.
    static var userIntent: Bool {
        UserDefaults.standard.bool(forKey: intentKey)
    }

    /// Czy macOS faktycznie ma zarejestrowany i aktywny login item.
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Surowy status systemowy — do logów i diagnostyki UI.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Włącza/wyłącza autostart i zapisuje intencję. Rzuca, gdy SMAppService
    /// odmówi — wywołujący MUSI obsłużyć błąd (pokazać go), a nie połykać.
    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(enabled, forKey: intentKey)
            if enabled {
                UserDefaults.standard.set(Bundle.main.bundlePath, forKey: registeredPathKey)
            } else {
                UserDefaults.standard.removeObject(forKey: registeredPathKey)
            }
            log.notice("setEnabled(\(enabled, privacy: .public)) OK — status=\(SMAppService.mainApp.status.rawValue, privacy: .public)")
        } catch {
            log.error("setEnabled(\(enabled, privacy: .public)) FAILED: \(error.localizedDescription, privacy: .public) — status=\(SMAppService.mainApp.status.rawValue, privacy: .public)")
            throw error
        }
    }

    private static let registeredPathKey = "launchAtLoginRegisteredPath"

    /// Wołane przy starcie aplikacji. Uzgadnia rejestrację login itemu z realnym
    /// stanem systemu.
    ///
    /// Kluczowy przypadek: `status` potrafi raportować `.enabled`, podczas gdy
    /// wpis BTM wskazuje na STARĄ ścieżkę bundla (np. usunięty `~/Applications`)
    /// — wtedy macOS nie ma czego odpalić i autostart „nie działa", choć system
    /// twierdzi, że jest włączony. Dlatego przy pierwszym starcie z danej ścieżki
    /// wymuszamy czyste przepięcie (`unregister`+`register`) na bieżący bundle.
    /// Znacznik w UserDefaults gwarantuje, że robimy to raz na ścieżkę, bez
    /// churnu przy każdym logowaniu.
    static func reconcileOnLaunch() {
        let current = status
        let bundlePath = Bundle.main.bundlePath
        let registeredPath = UserDefaults.standard.string(forKey: registeredPathKey)
        log.notice("reconcileOnLaunch: intent=\(userIntent, privacy: .public) status=\(current.rawValue, privacy: .public)")
        Diag.log("LaunchAtLogin", "reconcileOnLaunch: intent=\(userIntent) status=\(current.rawValue) (0=notReg 1=enabled 2=requiresApproval 3=notFound) bundle=\(bundlePath) registeredPath=\(registeredPath ?? "nil")")
        guard userIntent else { return }

        // Odśwież, gdy: nie jest enabled, ALBO nie potwierdziliśmy rejestracji
        // dokładnie dla tej ścieżki bundla (czyli potencjalnie stała stara).
        let needsRefresh = current != .enabled || registeredPath != bundlePath
        guard needsRefresh else { return }

        do {
            // Najpierw zdejmij ewentualny stary (być może stale-path) wpis, potem
            // zarejestruj świeżo na bieżącą ścieżkę.
            try? SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(bundlePath, forKey: registeredPathKey)
            log.notice("reconcileOnLaunch: refreshed registration -> status \(SMAppService.mainApp.status.rawValue, privacy: .public)")
            Diag.log("LaunchAtLogin", "refreshed registration to \(bundlePath) -> status \(SMAppService.mainApp.status.rawValue)")
        } catch {
            log.error("reconcileOnLaunch: register FAILED: \(error.localizedDescription, privacy: .public)")
            Diag.log("LaunchAtLogin", "register FAILED: \(error.localizedDescription)")
        }
    }
}
