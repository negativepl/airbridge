import AppKit

/// Picks the browser a link from the phone opens in. The choice is a setting
/// (`preferenceKey`): the browser in use (the default), the system default, or
/// one specific browser. "In use" means, in order:
/// 1. a browser that is the frontmost app;
/// 2. the browser that was frontmost most recently (tracked since launch);
/// 3. any running browser;
/// 4. nil: nothing is running, so the system default opens it.
/// A "browser" is any app macOS lists as able to open https links.
@MainActor
final class BrowserPicker {
    static let shared = BrowserPicker()

    /// UserDefaults key: `inUse`, `systemDefault`, or a browser's bundle id.
    static let preferenceKey = "linkBrowser"
    static let inUse = "inUse"
    static let systemDefault = "systemDefault"

    struct Browser: Identifiable {
        let id: String      // bundle id
        let name: String
        let url: URL
    }

    /// Bundle id of the browser that was last activated, newest wins.
    private var lastActiveBrowser: String?
    private var observer: NSObjectProtocol?

    private init() {}

    /// Starts following app activations. Idempotent.
    func startTracking() {
        guard observer == nil else { return }
        if let front = NSWorkspace.shared.frontmostApplication, isBrowser(front) {
            lastActiveBrowser = front.bundleIdentifier
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            let browser = app.map { BrowserPicker.browserURLs().contains($0.bundleURL?.standardizedFileURL ?? URL(fileURLWithPath: "/")) } ?? false
            MainActor.assumeIsolated {
                if browser { BrowserPicker.shared.lastActiveBrowser = bundleId }
            }
        }
    }

    /// Opens the link in the chosen browser and brings it forward.
    func open(_ url: URL) {
        guard let appURL = chooseBrowserURL() else {
            NSWorkspace.shared.open(url)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            // The chosen browser refused (it quit in the meantime, say): fall back
            // to the default rather than dropping the link.
            if error != nil {
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
    }

    /// The app to open with, or nil for the system default.
    private func chooseBrowserURL() -> URL? {
        let choice = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? Self.inUse
        switch choice {
        case Self.inUse:
            return browserInUse()?.bundleURL
        case Self.systemDefault:
            return nil
        default:
            // A browser picked in Settings; launched if it is not running. If it
            // has since been removed, fall back to the one in use.
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice) ?? browserInUse()?.bundleURL
        }
    }

    private func browserInUse() -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications.filter { isBrowser($0) && !$0.isTerminated }
        if let front = NSWorkspace.shared.frontmostApplication, running.contains(front) {
            return front
        }
        if let last = lastActiveBrowser, let app = running.first(where: { $0.bundleIdentifier == last }) {
            return app
        }
        return running.first
    }

    private func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL?.standardizedFileURL else { return false }
        return Self.browserURLs().contains(url)
    }

    /// Browsers installed on this Mac, for the setting, sorted by name.
    static func installedBrowsers() -> [Browser] {
        var seen = Set<String>()
        return browserURLs().compactMap { url -> Browser? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return Browser(id: id, name: name, url: url)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Apps registered for https links, as macOS reports them.
    nonisolated private static func browserURLs() -> Set<URL> {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: probe).map(\.standardizedFileURL))
    }
}
