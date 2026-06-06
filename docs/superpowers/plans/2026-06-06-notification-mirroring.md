# Notification Mirroring (Android → Mac) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Powiadomienia z Androida pokazywane natywnie na macOS (`UNUserNotificationCenter`), z filtrem per-app w ustawieniach Maca. Display-only.

**Architecture:** Android `NotificationListenerService` odsiewa szum → wysyła `NotificationPosted` przez istniejący WebSocket (most przez `AirbridgeService` companion) → macOS `NotificationService` filtruje po blackliście i pokazuje natywny banner. Filtr per-app i lista apek po stronie Maca (`UserDefaults`).

**Tech Stack:** Kotlin (NotificationListenerService, JUnit), Swift (UserNotifications, XCTest, SwiftUI). Testy: Kotlin `./gradlew :app:testDebugUnitTest`, Swift `swift test`. System-level (listener, UNUserNotificationCenter) — weryfikacja ręczna.

---

## File Structure

- `android/.../protocol/Message.kt` — `NotificationPosted` (toJson + fromJson).
- `android/.../notification/NotificationFilter.kt` (NOWY) — czysta `shouldRelayNotification(...)`.
- `android/.../notification/NotificationRelayService.kt` (NOWY) — listener, używa filtru + mostu.
- `android/.../service/AirbridgeService.kt` — companion `relayNotification(...)` (most jak `requestMacInfo`).
- `android/.../AndroidManifest.xml` — service + permission.
- `android/.../ui/OnboardingScreen.kt`, `SettingsScreen.kt` — uprawnienie notification-listener.
- macOS `Protocol/Message.swift` — `notificationPosted`.
- macOS `Services/NotificationService.swift` (NOWY) — UNUserNotificationCenter + filtr + knownApps.
- macOS `Services/ConnectionService.swift` — routing; `AirbridgeApp.swift` — wiring.
- macOS `Views/SettingsView.swift` — sekcja per-app.
- Testy: `Message.kt`/`Message.swift` round-trip, `NotificationFilter` (Kotlin).

**Kolejność:** protokół (Kotlin, Swift) → filtr szumu → Android listener+most+manifest → Android uprawnienie → macOS service+wiring → macOS ustawienia → weryfikacja.

---

## Task 1: Protokół Kotlin — `NotificationPosted`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` (data class + toJson; fromJson case)
- Test: `android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt`

- [ ] **Step 1: Failing test** — append to `MessageTest.kt`:

```kotlin
    @Test fun notificationPostedRoundTrip() {
        val msg = Message.NotificationPosted(
            packageName = "com.whatsapp", appName = "WhatsApp",
            title = "Mama", text = "Zadzwoń", timestamp = 1_700_000_000_000, appIcon = "QQ=="
        )
        val parsed = Message.fromJson(msg.toJson()) as Message.NotificationPosted
        assertEquals("com.whatsapp", parsed.packageName)
        assertEquals("WhatsApp", parsed.appName)
        assertEquals("Mama", parsed.title)
        assertEquals("Zadzwoń", parsed.text)
        assertEquals(1_700_000_000_000, parsed.timestamp)
        assertEquals("QQ==", parsed.appIcon)
    }

    @Test fun notificationPostedDefaultsWhenIconMissing() {
        val legacy = """{"type":"notification_posted","package_name":"a","app_name":"A","title":"t","text":"x","timestamp":1}"""
        val parsed = Message.fromJson(legacy) as Message.NotificationPosted
        assertEquals("", parsed.appIcon)
    }
```

- [ ] **Step 2: Run, verify FAIL:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.MessageTest"`

- [ ] **Step 3: Add data class** in `Message.kt` (after an existing data class, e.g. near other request/update types):

```kotlin
    data class NotificationPosted(
        val packageName: String,
        val appName: String,
        val title: String,
        val text: String,
        val timestamp: Long,
        val appIcon: String = ""
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "notification_posted")
            put("package_name", packageName)
            put("app_name", appName)
            put("title", title)
            put("text", text)
            put("timestamp", timestamp)
            put("app_icon", appIcon)
        }.toString()
    }
```

- [ ] **Step 4: Add fromJson case** (in the `when` in `fromJson`):

```kotlin
                "notification_posted" -> NotificationPosted(
                    packageName = obj.getString("package_name"),
                    appName = obj.getString("app_name"),
                    title = obj.getString("title"),
                    text = obj.getString("text"),
                    timestamp = obj.getLong("timestamp"),
                    appIcon = obj.optString("app_icon", "")
                )
```

- [ ] **Step 5: Run, verify PASS.** Same command as Step 2.

- [ ] **Step 6: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt
git commit -m "feat(android-protocol): NotificationPosted message"
```

---

## Task 2: Protokół Swift — `notificationPosted`

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift` (enum case, TypeKey, CodingKeys, encode, decode)
- Test: `macos/Airbridge/Tests/ProtocolTests/MessageTests.swift`

- [ ] **Step 1: Failing tests** — append to `MessageTests.swift`:

```swift
    func testNotificationPostedRoundTrip() throws {
        let msg = Message.notificationPosted(packageName: "com.whatsapp", appName: "WhatsApp",
                                             title: "Mama", text: "Zadzwoń",
                                             timestamp: 1_700_000_000_000, appIcon: "QQ==")
        let data = try JSONEncoder().encode(msg)
        XCTAssertEqual(try JSONDecoder().decode(Message.self, from: data), msg)
    }

    func testNotificationPostedLegacyNoIcon() throws {
        let legacy = #"{"type":"notification_posted","package_name":"a","app_name":"A","title":"t","text":"x","timestamp":1}"#
        let decoded = try JSONDecoder().decode(Message.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded, .notificationPosted(packageName: "a", appName: "A", title: "t", text: "x", timestamp: 1, appIcon: ""))
    }
```

- [ ] **Step 2: Run, verify FAIL:** `cd macos/Airbridge && swift test --filter MessageTests`

- [ ] **Step 3: Add enum case** (near other cases):
```swift
    case notificationPosted(packageName: String, appName: String, title: String, text: String, timestamp: Int64, appIcon: String)
```

- [ ] **Step 4: Add TypeKey** (in `private enum TypeKey`):
```swift
        case notificationPosted = "notification_posted"
```

- [ ] **Step 5: Add CodingKeys** (only those not already present — `title`, `text`, `timestamp` likely exist; add the missing ones):
```swift
        case packageName = "package_name"
        case appName     = "app_name"
        case appIcon     = "app_icon"
```
(If `packageName` already exists from another message, do NOT duplicate. `title`/`text` — check; add if absent.)

- [ ] **Step 6: Add encode case** (in `encode(to:)`):
```swift
        case .notificationPosted(let packageName, let appName, let title, let text, let timestamp, let appIcon):
            try container.encode(TypeKey.notificationPosted.rawValue, forKey: .type)
            try container.encode(packageName, forKey: .packageName)
            try container.encode(appName, forKey: .appName)
            try container.encode(title, forKey: .title)
            try container.encode(text, forKey: .text)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(appIcon, forKey: .appIcon)
```

- [ ] **Step 7: Add decode case** (in `init(from:)`), with legacy default for `appIcon`:
```swift
        case .notificationPosted:
            let packageName = try container.decode(String.self, forKey: .packageName)
            let appName = try container.decode(String.self, forKey: .appName)
            let title = try container.decode(String.self, forKey: .title)
            let text = try container.decode(String.self, forKey: .text)
            let timestamp = try container.decode(Int64.self, forKey: .timestamp)
            let appIcon = try container.decodeIfPresent(String.self, forKey: .appIcon) ?? ""
            self = .notificationPosted(packageName: packageName, appName: appName, title: title, text: text, timestamp: timestamp, appIcon: appIcon)
```

- [ ] **Step 8: Run, verify PASS.** Same as Step 2.

- [ ] **Step 9: Commit:**
```bash
git add macos/Airbridge/Sources/Protocol/Message.swift macos/Airbridge/Tests/ProtocolTests/MessageTests.swift
git commit -m "feat(macos-protocol): notificationPosted message"
```

---

## Task 3: Android — czysta funkcja odsiewania szumu

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/notification/NotificationFilter.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/notification/NotificationFilterTest.kt`

- [ ] **Step 1: Failing test** — create `NotificationFilterTest.kt`:

```kotlin
package com.airbridge.notification

import android.app.Notification
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationFilterTest {
    private val own = "com.airbridge"

    @Test fun relaysNormalNotification() {
        assertTrue(shouldRelayNotification(flags = 0, packageName = "com.whatsapp", ownPackage = own, title = "A", text = "B"))
    }
    @Test fun skipsOngoing() {
        assertFalse(shouldRelayNotification(flags = Notification.FLAG_ONGOING_EVENT, packageName = "x", ownPackage = own, title = "A", text = "B"))
    }
    @Test fun skipsGroupSummary() {
        assertFalse(shouldRelayNotification(flags = Notification.FLAG_GROUP_SUMMARY, packageName = "x", ownPackage = own, title = "A", text = "B"))
    }
    @Test fun skipsOwnApp() {
        assertFalse(shouldRelayNotification(flags = 0, packageName = own, ownPackage = own, title = "A", text = "B"))
    }
    @Test fun skipsEmpty() {
        assertFalse(shouldRelayNotification(flags = 0, packageName = "x", ownPackage = own, title = null, text = "  "))
    }
    @Test fun relaysTitleOnly() {
        assertTrue(shouldRelayNotification(flags = 0, packageName = "x", ownPackage = own, title = "A", text = null))
    }
}
```

- [ ] **Step 2: Run, verify FAIL:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.notification.NotificationFilterTest"`

- [ ] **Step 3: Create** `NotificationFilter.kt`:

```kotlin
package com.airbridge.notification

import android.app.Notification

/**
 * Czy dane powiadomienie warto przekazać na Maca. Odsiewa szum: trwałe (ongoing),
 * grupowe podsumowania, własne powiadomienia Airbridge i puste (brak tytułu i treści).
 */
fun shouldRelayNotification(
    flags: Int,
    packageName: String,
    ownPackage: String,
    title: String?,
    text: String?
): Boolean {
    if (flags and Notification.FLAG_ONGOING_EVENT != 0) return false
    if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
    if (packageName == ownPackage) return false
    if (title.isNullOrBlank() && text.isNullOrBlank()) return false
    return true
}
```

- [ ] **Step 4: Run, verify PASS (6 tests).** Same as Step 2.

- [ ] **Step 5: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/notification/NotificationFilter.kt android/Airbridge/app/src/test/java/com/airbridge/notification/NotificationFilterTest.kt
git commit -m "feat(android): pure shouldRelayNotification filter"
```

---

## Task 4: Android — NotificationRelayService + most + manifest

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/notification/NotificationRelayService.kt`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt` (companion `relayNotification`)
- Modify: `android/Airbridge/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add the relay bridge to `AirbridgeService` companion.** READ the companion (around line 55-130) — it has `@Volatile private var instance: AirbridgeService?` and `fun requestMacInfo()`. Add an analogous static method that sends a NotificationPosted when connected. Mirror exactly how `requestMacInfo` reaches the instance + websocket:

```kotlin
        /** Most z NotificationRelayService: wyślij powiadomienie na Maca, gdy połączony. */
        fun relayNotification(
            packageName: String, appName: String, title: String, text: String,
            timestamp: Long, appIcon: String
        ) {
            val svc = instance ?: return
            if (!svc.isConnected.value) return
            svc.serviceScope.launch {
                try {
                    svc.webSocketClient.send(
                        Message.NotificationPosted(packageName, appName, title, text, timestamp, appIcon)
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "relayNotification failed", e)
                }
            }
        }
```
Adapt member names (`isConnected`, `serviceScope`, `webSocketClient`, `TAG`) to the actual ones used by `requestMacInfo`. If `webSocketClient`/`serviceScope` are private, follow the same access pattern `requestMacInfo` uses (it already reaches them from the companion).

- [ ] **Step 2: Create** `NotificationRelayService.kt`:

```kotlin
package com.airbridge.notification

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.app.Notification
import com.airbridge.service.AirbridgeService
import java.io.ByteArrayOutputStream

class NotificationRelayService : NotificationListenerService() {

    private val iconCache = HashMap<String, String>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (!shouldRelayNotification(n.flags, sbn.packageName, packageName, title, text)) return

        val pm = applicationContext.packageManager
        val appName = try {
            pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (e: Exception) { sbn.packageName }

        val icon = iconCache.getOrPut(sbn.packageName) {
            try { encodeAppIcon(pm.getApplicationIcon(sbn.packageName)) } catch (e: Exception) { "" }
        }

        AirbridgeService.relayNotification(
            packageName = sbn.packageName,
            appName = appName,
            title = title ?: "",
            text = text ?: "",
            timestamp = sbn.postTime,
            appIcon = icon
        )
    }

    /** Drawable ikony aplikacji → 96px PNG → base64. */
    private fun encodeAppIcon(drawable: Drawable): String {
        val size = 96
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            bmp
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}
```

- [ ] **Step 3: Register service in `AndroidManifest.xml`.** Inside `<application>`, next to the other `<service>` blocks (e.g. after `MirrorAccessibilityService`), add:

```xml
        <service
            android:name=".notification.NotificationRelayService"
            android:label="@string/app_name"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="false">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
```

- [ ] **Step 4: Compile + tests.**
```bash
cd android/Airbridge && ./gradlew :app:compileDebugKotlin && ./gradlew :app:testDebugUnitTest
```
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/notification/NotificationRelayService.kt android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt android/Airbridge/app/src/main/AndroidManifest.xml
git commit -m "feat(android): NotificationListenerService relays notifications over websocket"
```

---

## Task 5: Android — uprawnienie notification-listener (onboarding + ustawienia)

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt` (PermissionsPage)
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/SettingsScreen.kt`

- [ ] **Step 1: Add a notification-listener PermissionRow in `OnboardingScreen.PermissionsPage`.** READ the existing `PermissionsPage` and the `PermissionRow`/launcher pattern (e.g. how `overlay` optional permission opens a Settings screen and re-checks state). Add:
  - State: `var notifListenerGranted by remember { mutableStateOf(isNotificationListenerEnabled(context)) }`.
  - A launcher that opens `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` and on return re-checks `isNotificationListenerEnabled(context)`:
    ```kotlin
    val notifListenerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { notifListenerGranted = isNotificationListenerEnabled(context) }
    ```
  - A `PermissionRow` (icon `Icons.Rounded.Notifications` or similar): tytuł „Powiadomienia" / "Notifications", opis „Pokazuj powiadomienia z telefonu na Macu", granted = `notifListenerGranted`, onRequest = `{ notifListenerLauncher.launch(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }`.
  - This permission is **optional**: do NOT add it to `allGranted` (matches how overlay is optional).

- [ ] **Step 2: Add the `isNotificationListenerEnabled` helper** (top-level in OnboardingScreen.kt or a shared util):
```kotlin
fun isNotificationListenerEnabled(context: android.content.Context): Boolean {
    val flat = android.provider.Settings.Secure.getString(
        context.contentResolver, "enabled_notification_listeners"
    ) ?: return false
    val pkg = context.packageName
    return flat.split(":").any { it.startsWith("$pkg/") }
}
```

- [ ] **Step 3: Add an entry in `SettingsScreen`** so users can reach it after onboarding. READ `SettingsScreen.kt` patterns (how a row opens a system settings screen). Add a row „Powiadomienia" that launches `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` and shows enabled/disabled via `isNotificationListenerEnabled`.

- [ ] **Step 4: Compile.**
`cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt android/Airbridge/app/src/main/java/com/airbridge/ui/SettingsScreen.kt
git commit -m "feat(android): notification-listener permission in onboarding + settings"
```

---

## Task 6: macOS — `NotificationService` + wiring

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Services/NotificationService.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` (handler + routing)
- Modify: `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` (instancja + registerHandlers)

- [ ] **Step 1: Create** `NotificationService.swift`:

```swift
import Foundation
import UserNotifications
import Protocol

@Observable
@MainActor
final class NotificationService: MessageHandler {

    /// packageName -> appName, wykryte z napływających (dla listy w ustawieniach).
    private(set) var knownApps: [String: String] = [:]
    /// packageName, których powiadomienia są wyłączone.
    var disabledApps: Set<String> = []
    /// Globalny przełącznik.
    var enabled: Bool = true

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
```

- [ ] **Step 2: Route in `ConnectionService`.** Add `private var notificationHandler: MessageHandler?`, extend `registerHandlers(...)` with a `notifications: MessageHandler` parameter (assign it), and in `routeAuthenticatedMessage` add:
```swift
        case .notificationPosted:
            notificationHandler?.handleMessage(message)
```

- [ ] **Step 3: Wire in `AirbridgeApp.swift`.** After `let filesBrowser = FilesBrowserService()` (line ~38) add `let notifications = NotificationService()`. Update the `connection.registerHandlers(...)` call (line ~51) to pass `notifications: notifications`. If `NotificationService` needs to be held as a state/environment object like the others, mirror exactly how `filesBrowser`/`sms` are stored and injected.

- [ ] **Step 4: Build.** `cd macos/Airbridge && swift build`
Expected: Build complete. (Ignore SourceKit "No such module" false positives.)

- [ ] **Step 5: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/NotificationService.swift macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift
git commit -m "feat(macos): NotificationService shows native banners, per-app filter"
```

---

## Task 7: macOS — sekcja „Powiadomienia" w ustawieniach

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift`

- [ ] **Step 1: Inject `NotificationService` into `SettingsView`.** READ `SettingsView.swift` to see how it receives services (e.g. `@Environment`/`let` injected from `AirbridgeApp`). Add the `notificationService` the same way the other services reach this view.

- [ ] **Step 2: Add a `GlassSection`** (match existing sections' style):
```swift
    private var notificationsSection: some View {
        GlassSection(title: L10n.isPL ? "Powiadomienia" : "Notifications", systemImage: "bell.badge") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L10n.isPL ? "Pokazuj powiadomienia z telefonu" : "Show phone notifications",
                       isOn: Binding(get: { notificationService.enabled },
                                     set: { notificationService.setEnabled($0) }))
                    .font(.ab(.body))

                if notificationService.knownApps.isEmpty {
                    Text(L10n.isPL ? "Powiadomienia pojawią się tu, gdy telefon je przyśle."
                                   : "Apps will appear here once the phone sends notifications.")
                        .font(.ab(.subheadline)).foregroundStyle(.secondary)
                } else {
                    ForEach(notificationService.knownApps.sorted { $0.value < $1.value }, id: \.key) { pkg, name in
                        HStack {
                            Text(name).font(.ab(.body))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !notificationService.disabledApps.contains(pkg) },
                                set: { notificationService.setAppEnabled(pkg, $0) }
                            )).labelsHidden()
                        }
                        .disabled(!notificationService.enabled)
                    }
                }
            }
        }
    }
```

- [ ] **Step 3: Add `notificationsSection` to the settings body** where other sections are listed (match placement/spacing).

- [ ] **Step 4: Build.** `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 5: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift
git commit -m "feat(macos): per-app notification settings section"
```

---

## Task 8: Weryfikacja (build + ręczna e2e)

- [ ] **Step 1: Full tests.**
```bash
cd android/Airbridge && ./gradlew :app:testDebugUnitTest
cd ../../macos/Airbridge && swift test --filter MessageTests
```
Expected: PASS (Mirror integration failures pre-existing, unrelated).

- [ ] **Step 2: Build + install.** Android `./gradlew :app:assembleDebug` + install; macOS `scripts/dev-install.sh`.

- [ ] **Step 3: Manual e2e (Fold7 + Mac, połączone):**
  - W onboardingu/ustawieniach Androida włącz „Powiadomienia" → systemowy ekran notification access → zezwól Airbridge.
  - Na Macu zaakceptuj prośbę o powiadomienia (pierwsze uruchomienie).
  - Wyślij sobie powiadomienie na telefon (np. WhatsApp/SMS) → w ciągu sekundy natywny banner na Macu: tytuł, subtitle = nazwa apki, treść, ikona apki.
  - Trwałe/foreground (np. odtwarzacz) i własne powiadomienia Airbridge NIE pojawiają się.
  - W ustawieniach Maca wyłącz konkretną apkę → jej powiadomienia przestają się pokazywać; globalny przełącznik wyłącza wszystko.

- [ ] **Step 4: Commit ewentualnych poprawek.**

---

## Self-Review

- **Spec coverage:** protokół NotificationPosted Kotlin+Swift z legacy app_icon (Task 1,2) ✓; odsiewanie szumu jako czysta funkcja + test (Task 3) ✓; NotificationListenerService + most + manifest + ikona base64 cache (Task 4) ✓; uprawnienie onboarding+settings, opcjonalne (Task 5) ✓; macOS UNUserNotificationCenter + filtr per-app blacklist + knownApps + attachment ikony (Task 6) ✓; ustawienia per-app (Task 7) ✓; weryfikacja e2e (Task 8) ✓.
- **Type consistency:** `NotificationPosted(packageName, appName, title, text, timestamp, appIcon)` spójne Kotlin↔Swift↔relayNotification↔NotificationService; `shouldRelayNotification(flags, packageName, ownPackage, title, text)` (Task 3↔4); `notificationHandler`/`registerHandlers(..., notifications:)` (Task 6↔3-wiring); `knownApps`/`disabledApps`/`enabled`/`setAppEnabled`/`setEnabled` (Task 6↔7).
- **Placeholders:** integracyjne kroki (companion most, onboarding/settings rows, SettingsView injection, AirbridgeApp wiring) celowo instruują „READ X, mirror pattern" z konkretnymi nazwami i intencją — bo dokładny kształt zależy od istniejącego kodu; kluczowe nowe pliki mają pełny kod.
