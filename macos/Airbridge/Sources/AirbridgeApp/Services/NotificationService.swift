import Foundation
import UserNotifications
import Protocol

/// Pokazuje powiadomienia z telefonu natywnie na macOS (UNUserNotificationCenter),
/// z filtrem per-app. Display-only.
@Observable
@MainActor
final class NotificationService: MessageHandler {

    /// packageName -> appName, wykryte z napływających (dla listy w ustawieniach).
    private(set) var knownApps: [String: String] = [:]
    /// packageName, których powiadomienia są wyłączone (blacklista).
    private(set) var disabledApps: Set<String> = []
    /// Globalny przełącznik.
    private(set) var enabled: Bool = true

    private let knownKey = "notif.knownApps"
    private let disabledKey = "notif.disabledApps"
    private let enabledKey = "notif.enabled"

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: enabledKey) != nil { enabled = d.bool(forKey: enabledKey) }
        disabledApps = Set(d.stringArray(forKey: disabledKey) ?? [])
        if let dict = d.dictionary(forKey: knownKey) as? [String: String] { knownApps = dict }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    func setAppEnabled(_ packageName: String, _ on: Bool) {
        if on { disabledApps.remove(packageName) } else { disabledApps.insert(packageName) }
        UserDefaults.standard.set(Array(disabledApps), forKey: disabledKey)
    }

    func handleMessage(_ message: Message) {
        guard case let .notificationPosted(packageName, appName, title, text, _, appIcon) = message else { return }

        if knownApps[packageName] != appName {
            knownApps[packageName] = appName
            UserDefaults.standard.set(knownApps, forKey: knownKey)
        }

        guard enabled, !disabledApps.contains(packageName) else { return }

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? appName : title
        content.subtitle = appName
        content.body = text
        content.sound = .default

        if !appIcon.isEmpty, let attachment = Self.iconAttachment(base64: appIcon) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Zapisz base64 PNG do pliku temp i zrób UNNotificationAttachment.
    private static func iconAttachment(base64: String) -> UNNotificationAttachment? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("airbridge-notif-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: UUID().uuidString, url: url, options: nil)
        } catch {
            return nil
        }
    }
}
