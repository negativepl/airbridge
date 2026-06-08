import Foundation
import UserNotifications
import Protocol

/// Pokazuje powiadomienia z telefonu natywnie na macOS (UNUserNotificationCenter),
/// z filtrem per-app. Dla powiadomień z możliwością odpowiedzi (RemoteInput po stronie
/// Androida) dokłada natywne pole „Odpowiedz" i odsyła wpisany tekst na telefon.
@Observable
@MainActor
final class NotificationService: NSObject, MessageHandler, UNUserNotificationCenterDelegate {

    /// packageName -> appName, wykryte z napływających (dla listy w ustawieniach).
    private(set) var knownApps: [String: String] = [:]
    /// packageName, których powiadomienia są wyłączone (blacklista).
    private(set) var disabledApps: Set<String> = []
    /// Globalny przełącznik.
    private(set) var enabled: Bool = true

    private let knownKey = "notif.knownApps"
    private let disabledKey = "notif.disabledApps"
    private let enabledKey = "notif.enabled"

    /// Kategoria powiadomień z akcją odpowiedzi tekstowej.
    private static let replyCategoryId = "AIRBRIDGE_REPLYABLE"
    private static let replyActionId = "AIRBRIDGE_REPLY"

    @ObservationIgnored private weak var connectionService: ConnectionService?

    override init() {
        super.init()
        let d = UserDefaults.standard
        if d.object(forKey: enabledKey) != nil { enabled = d.bool(forKey: enabledKey) }
        disabledApps = Set(d.stringArray(forKey: disabledKey) ?? [])
        if let dict = d.dictionary(forKey: knownKey) as? [String: String] { knownApps = dict }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyActionId,
            title: L10n.isPL ? "Odpowiedz" : "Reply",
            options: [],
            textInputButtonTitle: L10n.isPL ? "Wyślij" : "Send",
            textInputPlaceholder: L10n.isPL ? "Odpowiedź…" : "Reply…"
        )
        let category = UNNotificationCategory(
            identifier: Self.replyCategoryId,
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func configure(connectionService: ConnectionService) {
        self.connectionService = connectionService
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
        guard case let .notificationPosted(packageName, appName, title, text, _, appIcon, notificationKey, canReply) = message else { return }

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

        // Powiadomienia z akcją reply (np. WhatsApp): dołącz natywne pole odpowiedzi.
        if canReply, !notificationKey.isEmpty {
            content.categoryIdentifier = Self.replyCategoryId
            content.userInfo = ["notificationKey": notificationKey]
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Pokazuj banery także gdy aplikacja jest na wierzchu.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Użytkownik wpisał odpowiedź w banerze → odeślij tekst na telefon.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let textResponse = response as? UNTextInputNotificationResponse,
           let key = response.notification.request.content.userInfo["notificationKey"] as? String,
           !key.isEmpty {
            let reply = textResponse.userText
            Task { @MainActor in self.sendReply(notificationKey: key, text: reply) }
        }
        completionHandler()
    }

    private func sendReply(notificationKey: String, text: String) {
        guard let connectionService, !text.isEmpty else { return }
        Task { try? await connectionService.broadcast(.notificationReply(notificationKey: notificationKey, text: text)) }
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
