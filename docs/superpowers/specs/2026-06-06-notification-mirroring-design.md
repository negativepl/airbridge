# Mirroring powiadomień Android → Mac

**Data:** 2026-06-06
**Status:** zaakceptowany design
**Branch:** `feat/notifications` (z czystego, wypchniętego mastera)

## Cel

Powiadomienia z telefonu (Android) pojawiają się **natywnie na macOS** (`UNUserNotificationCenter`).
Użytkownik w ustawieniach Maca wybiera, których aplikacji powiadomienia pokazywać.
MVP: **tylko wyświetlanie** (display-only), bez akcji.

## Decyzje

- **Display-only.** Bez klikania/odpowiadania/synchronizacji odrzucenia. (YAGNI — później.)
- **Domyślnie wszystkie** apki pokazywane (po odsianiu szumu); użytkownik wyłącza niechciane.
- **Filtr per-app po stronie Maca** (blacklista wyłączonych w `UserDefaults`); Android wysyła wszystko
  (po odsianiu oczywistego szumu u źródła).
- Jednokierunkowo telefon→Mac. Niepołączony = nie wysyła (bez kolejkowania offline).

## A. Android — `NotificationListenerService`

- Nowy serwis `notification/NotificationRelayService` extends `android.service.notification.NotificationListenerService`
  (manifest: `android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"`,
  intent-filter `android.service.notification.NotificationListenerService`).
- Special permission włączany przez użytkownika w ustawieniach systemowych (jak Accessibility mirrora) —
  `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`; stan sprawdzany przez
  `NotificationManager.isNotificationListenerAccessGranted(ComponentName)` (lub
  `Settings.Secure "enabled_notification_listeners"`).
- **`onNotificationPosted(sbn)`** — odsiewanie szumu PRZED wysłaniem (pomiń, gdy):
  - `sbn.notification.flags and (FLAG_ONGOING_EVENT or FLAG_GROUP_SUMMARY) != 0`,
  - `sbn.packageName == applicationContext.packageName` (własne powiadomienia Airbridge),
  - brak treści: `title.isNullOrBlank() && text.isNullOrBlank()`.
- Z `sbn.notification.extras` czyta `EXTRA_TITLE`, `EXTRA_TEXT`; `appName` z `PackageManager`
  (`getApplicationLabel`); `appIcon` z `getApplicationIcon` → bitmapa → skala ~96px → PNG → base64
  (**cache per `packageName`** w pamięci serwisu, by nie przeliczać).
- Wysyłka: serwis przekazuje do `AirbridgeService` (statyczny most jak istniejące, np. companion/
  `AirbridgeService.sendNotification(...)`), które robi `webSocketClient.send(Message.NotificationPosted(...))`
  tylko gdy połączony. Wzorzec: jak `requestMacInfo()` / statyczne API serwisu.

## B. Protokół (Kotlin `Message.kt` + Swift `Message.swift`)

`NotificationPosted` — typ `notification_posted`:
| pole | typ | json |
|------|-----|------|
| packageName | String | `package_name` |
| appName | String | `app_name` |
| title | String | `title` |
| text | String | `text` |
| timestamp | Long/Int64 | `timestamp` |
| appIcon | String (base64 PNG, może być "") | `app_icon` |

Round-trip testy po obu stronach (Kotlin: toJson→fromJson; Swift: encode→decode + legacy bez `app_icon`).
Jednokierunkowy: Kotlin głównie `toJson` (telefon wysyła), Swift `decode` (Mac odbiera) — ale dla testów
round-trip dodać też dekodowanie po stronie Kotlin (jak inne typy) i encode po stronie Swift.

## C. macOS — `NotificationService` (`MessageHandler`, `@Observable @MainActor`)

- Przy starcie/`configure`: `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`.
- `handleMessage(.notificationPosted(...))`:
  - jeśli `packageName` w blacklist (`disabledApps`) → pomiń;
  - dorzuć `packageName`/`appName` do `knownApps` (persist) — dla listy w ustawieniach;
  - zbuduj `UNMutableNotificationContent`: `title` = title, `subtitle` = appName, `body` = text;
  - gdy `appIcon` niepuste → zapis base64 do pliku temp → `UNNotificationAttachment` (ikona w bannerze);
  - `UNNotificationRequest(identifier: UUID, content, trigger: nil)` → `add`.
- Stan persist (`UserDefaults`): `disabledApps: Set<String>` (blacklista po packageName),
  `knownApps: [packageName: appName]`.
- Rejestracja w `ConnectionService`: nowy `notificationHandler`, case `.notificationPosted` w
  `routeAuthenticatedMessage`, wiring w `AirbridgeApp`.

## D. macOS — ustawienia (`SettingsView`)

- Nowa `GlassSection` „Powiadomienia" / "Notifications":
  - globalny `Toggle` „Pokazuj powiadomienia z telefonu" (master on/off, w `UserDefaults`);
  - lista `knownApps` (posortowana po `appName`) — każda z `Toggle` (włączone = nie w blacklist);
    przełączenie aktualizuje `disabledApps`.
  - gdy `knownApps` puste: hint „Powiadomienia pojawią się tu, gdy telefon je przyśle".

## E. Uprawnienia / onboarding

- Android: nowy `PermissionRow` w `OnboardingScreen.PermissionsPage` („Powiadomienia" → otwiera
  `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`), stan z `isNotificationListenerEnabled`.
  Dodać też wejście w `SettingsScreen` (sekcja jak inne uprawnienia). Uprawnienie **opcjonalne**
  (nie blokuje `allGranted` onboardingu — feature dodatkowy).
- macOS: zgoda na powiadomienia systemowe (prompt z `requestAuthorization`).

## Testy / weryfikacja

- Round-trip protokołu `NotificationPosted` (Kotlin + Swift, w tym legacy bez `app_icon`).
- Odsiewanie szumu — czysta, testowalna funkcja `shouldRelayNotification(flags, packageName, ownPackage, title, text)` (Kotlin unit test).
- Filtr per-app macOS — logika blacklisty jako czysta funkcja/metoda (jeśli wydzielalna) lub weryfikacja ręczna.
- `NotificationListenerService` (system), `UNUserNotificationCenter` (system) — weryfikacja ręczna e2e na Fold7 + Macu.

## Poza zakresem (YAGNI)

Akcje (klik/reply/dismiss-sync), kolejkowanie offline, historia powiadomień w UI aplikacji,
rozwijanie wątków/grup, dźwięki per-app, „nie przeszkadzać". Później.

## Pliki dotknięte

- `android/.../AndroidManifest.xml` — serwis + permission.
- `android/.../notification/NotificationRelayService.kt` (NOWY) + filtr szumu (czysta funkcja).
- `android/.../protocol/Message.kt` — `NotificationPosted`.
- `android/.../service/AirbridgeService.kt` — statyczny most wysyłki.
- `android/.../ui/OnboardingScreen.kt` + `SettingsScreen.kt` — uprawnienie.
- macOS `Protocol/Message.swift` — `notificationPosted`.
- macOS `Services/NotificationService.swift` (NOWY) + `ConnectionService.swift` (routing) + `AirbridgeApp.swift` (wiring).
- macOS `Views/SettingsView.swift` — sekcja per-app.
- Testy: `Message.kt`/`Message.swift` round-trip, filtr szumu (Kotlin).
