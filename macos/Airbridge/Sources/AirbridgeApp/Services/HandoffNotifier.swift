import Foundation
import UserNotifications

/// Posts the "headphones auto-switched" notification with a Move-back action.
///
/// `NotificationService` is already installed as the app's sole
/// `UNUserNotificationCenterDelegate` (phone-notification mirroring, with a
/// reply action). `UNUserNotificationCenter.delegate` is a single slot, so
/// this class does NOT install its own delegate — it registers its category
/// and lets `NotificationService.userNotificationCenter(_:didReceive:...)`
/// forward matching action identifiers to `handleAction(_:)` instead.
@MainActor
final class HandoffNotifier {

    static let categoryId = "HEADPHONE_HANDOFF"
    static let moveBackActionId = "MOVE_BACK"

    private var moveBackHandler: (() -> Void)?

    init() {
        registerCategory()
    }

    /// Authorization is requested lazily (also already requested by
    /// `NotificationService` at launch) — harmless to call again here so this
    /// class works standalone if that ever changes.
    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Merges our category into whatever set is already registered instead of
    /// replacing it — `setNotificationCategories` overwrites the whole set,
    /// and `NotificationService` registers its own reply category. Neither
    /// `UNUserNotificationCenter` nor `UNNotificationCategory` is `Sendable`,
    /// so nothing from `self` crosses into the `@Sendable` completion — it
    /// only carries the plain identifiers/title needed to rebuild the
    /// category on the other side.
    private func registerCategory() {
        let categoryId = Self.categoryId
        let actionId = Self.moveBackActionId
        let title = L10n.isPL ? "Przenieś z powrotem" : "Move back"
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            let moveBackAction = UNNotificationAction(identifier: actionId, title: title, options: [])
            let category = UNNotificationCategory(
                identifier: categoryId,
                actions: [moveBackAction],
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories(existing.union([category]))
        }
    }

    /// Posts the "switched to Mac" notification. `onMoveBack` fires when the
    /// user taps the Move-back action (routed via `handleAction`).
    func postSwitched(onMoveBack: @escaping () -> Void) {
        moveBackHandler = onMoveBack
        requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = "AirBridge"
        content.body = L10n.isPL ? "Słuchawki przełączone na Maca" : "Headphones switched to Mac"
        content.sound = .default
        content.categoryIdentifier = Self.categoryId

        let request = UNNotificationRequest(identifier: "headphone-handoff", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Called by `NotificationService`'s delegate callback for any action on
    /// any notification; ignores everything except our own action id.
    func handleAction(_ actionIdentifier: String) {
        guard actionIdentifier == Self.moveBackActionId else { return }
        let handler = moveBackHandler
        moveBackHandler = nil
        handler?()
    }
}
