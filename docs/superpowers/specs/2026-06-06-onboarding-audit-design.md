# Audyt i aktualizacja kreatorów konfiguracji (onboarding) — Android + macOS

**Data:** 2026-06-06
**Status:** zaakceptowany design
**Branch:** `feat/notifications` (kontynuacja — onboarding rozszerza m.in. powiadomienia)

## Cel

Zaktualizować wizardy onboardingu obu aplikacji, by odzwierciedlały OBECNY zestaw funkcji
i uprawnień (doszły: pliki, ładowanie, powiadomienia, mirror, reverse control). Umożliwić
włączenie wszystkich uprawnień (w tym ułatwień dostępu / accessibility) z poziomu wizarda.

## Wynik audytu (co jest nie tak)

**Android** (`OnboardingScreen.kt`, 4 strony, `PermissionsPage`): pokrywa SMS, zdjęcia,
kontakty, pliki, powiadomienia (POST_NOTIFICATIONS), overlay, notification-listener — ale
**BRAK włącznika Accessibility** (`MirrorAccessibilityService` — reverse control), mimo że
usługa jest w manifeście. Feature-rows nie wspominają o mirrorze.

**macOS** (`OnboardingView.swift`, 3 strony): **w ogóle nie prosi o uprawnienia.** Accessibility
tylko w `SettingsView`, **Screen Recording nigdzie**, powiadomienia tylko w `SettingsView`.
`Info.plist` nie ma `NSScreenRecordingUsageDescription`.

## Decyzje

- **Accessibility i Screen Recording = opcjonalne** (potrzebne tylko do mirrora/sterowania),
  z jasnym opisem „do czego" i możliwością pominięcia/powrotu. Nie blokują onboardingu.
- Nie przebudowujemy wizardów od zera — dokładamy brakujące uprawnienia, porządkujemy
  wymagane vs opcjonalne, aktualizujemy teksty.

## A. Android — `OnboardingScreen.kt`

1. **Nowy wiersz Accessibility** w `PermissionsPage` (opcjonalny, wzór jak overlay):
   - ikona (np. `Icons.Rounded.TouchApp`), opis „Sterowanie telefonem z Maca",
   - `onRequest` → `Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)` przez launcher,
   - status: helper `isAccessibilityServiceEnabled(context)` sprawdzający, czy
     `com.airbridge/...MirrorAccessibilityService` jest w `Settings.Secure
     "enabled_accessibility_services"` (wzór jak `isNotificationListenerEnabled`).
   - NIE w `allGranted` (opcjonalne).
2. **Podział wizualny wymagane / opcjonalne**: po wierszach wymaganych (powiadomienia
   systemowe, SMS, zdjęcia, kontakty, pliki) dodać nagłówek sekcji „Dodatkowe — mirror i
   powiadomienia na Macu" / "Optional — mirroring & Mac notifications", pod którym: overlay,
   accessibility, notification-listener. Zwykły `Text` nagłówka między grupami (bez przebudowy
   `PermissionRow`).
3. **Feature-row / teksty**: na `WelcomePage` dopisać wzmiankę o mirrorze ekranu (nowy
   `FeatureRow` lub rozszerzenie istniejącego opisu); rozbudować `why` powiadomień
   (`onboarding_perm_notiflistener_why`) — że to powiadomienia telefonu na Macu, wybór apek
   po stronie Maca. Nowe stringi w `values/` + `values-pl/`.

## B. macOS — `OnboardingView.swift`

1. **Nowa strona „Uprawnienia"** (wstawiona przed stroną parowania; pager rośnie z 3 do 4):
   wiersze z opisem, statusem i przyciskiem „Przyznaj" (inline, wzór z `SettingsView`
   accessibility — `StatusIndicator` + grant + polling/onAppear re-check):
   - **Powiadomienia** — `UNUserNotificationCenter.requestAuthorization([.alert,.sound])`;
     status przez `getNotificationSettings`. (Banery z telefonu.)
   - **Dostępność (Accessibility)** — `AXIsProcessTrusted()`; grant przez
     `hotkeyService.requestAccessibilityAndStart()` (istniejące) lub otwarcie System Settings;
     polling jak w `SettingsView`. (Skrót Quick Drop + sterowanie telefonem.)
   - **Nagrywanie ekranu (Screen Recording)** — status `CGPreflightScreenCaptureAccess()`,
     prośba `CGRequestScreenCaptureAccess()` (lub otwarcie System Settings → Screen Recording).
     (Pokazywanie ekranu Maca na telefonie.)
   - **Sieć lokalna** — wiersz informacyjny (przyznawane systemowo przy pierwszym połączeniu),
     bez przycisku.
   - Wszystkie poza siecią **opcjonalne** — krótki opis „do czego", strona ma przycisk „Dalej"
     i „Pomiń".
2. `Info.plist`: dodać `NSScreenRecordingUsageDescription` (opis po co). Rozważyć opis
   Accessibility (macOS i tak pokazuje systemowy prompt).
3. Onboarding macOS dostaje dostęp do potrzebnych usług: prawdopodobnie `hotkeyService`
   (accessibility) i `notificationService` (status powiadomień) muszą być wstrzyknięte do
   `OnboardingView` z `AirbridgeApp` (jak inne serwisy). Screen Recording i tak idzie przez
   CoreGraphics (bez serwisu).

## Testy / weryfikacja

- Czyste, testowalne helpery Android: `isAccessibilityServiceEnabled(context)` —
  wydzielić logikę parsowania `enabled_accessibility_services` jako czystą funkcję
  `accessibilityServiceEnabled(flat: String?, component: String): Boolean` + unit test.
- Reszta (UI wizardów, systemowe prompty, CGRequestScreenCaptureAccess) — weryfikacja ręczna
  e2e (świeży onboarding na Fold7 + Macu: każde uprawnienie przyznawalne z wizarda, status
  odświeża się po powrocie).

## Poza zakresem (YAGNI)

- Przeprojektowanie układu/stylu wizardów. Reset onboardingu w ustawieniach. Wymuszanie
  uprawnień opcjonalnych. Strony per-funkcja (mirror tutorial itp.).

## Pliki dotknięte

- `android/.../ui/OnboardingScreen.kt` — wiersz accessibility, podział wymagane/opcjonalne,
  feature/teksty; helper accessibility (+ czysta funkcja do testu).
- `android/.../res/values/strings.xml` + `values-pl/strings.xml` — nowe stringi.
- `android/.../test/.../` — test czystej funkcji accessibility.
- macOS `Views/OnboardingView.swift` — nowa strona uprawnień.
- macOS `Resources/Info.plist` — `NSScreenRecordingUsageDescription`.
- macOS `AirbridgeApp.swift` — wstrzyknięcie potrzebnych serwisów do `OnboardingView`.
