# Onboarding Wizard Audit & Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zaktualizować wizardy onboardingu: Android dostaje wiersz Accessibility + podział wymagane/opcjonalne; macOS dostaje nową stronę uprawnień (Powiadomienia, Accessibility, Screen Recording, Sieć lokalna).

**Architecture:** Android — rozbudowa `PermissionsPage` o accessibility (czysta funkcja stanu + wiersz) i sekcję opcjonalną. macOS — nowa strona w `OnboardingView` z inline grant-buttonami (wzór z `SettingsView`), wstrzyknięcie `hotkeyService`/`notificationService`, `NSScreenRecordingUsageDescription` w Info.plist.

**Tech Stack:** Kotlin (Compose, JUnit), Swift (SwiftUI, UserNotifications, CoreGraphics screen-capture, ApplicationServices/AXIsProcessTrusted). Testy: czyste funkcje (Kotlin unit); wizardy/systemowe prompty — weryfikacja ręczna.

---

## Uwaga dla wykonawcy
Większość to UI wizardów (weryfikacja wizualna/ręczna). Jedyna jednostkowo testowalna część to czysta funkcja parsowania accessibility (Task 1). Reszta — build + ręczna e2e.

---

## Task 1: Android — czysta funkcja `accessibilityServiceEnabled` + test

**Files:**
- Create: `android/.../notification/` … nie — accessibility dotyczy mirror. Umieść w `android/Airbridge/app/src/main/java/com/airbridge/mirror/AccessibilityStatus.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/mirror/AccessibilityStatusTest.kt`

- [ ] **Step 1: Failing test** — `AccessibilityStatusTest.kt`:
```kotlin
package com.airbridge.mirror

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AccessibilityStatusTest {
    private val comp = "com.airbridge/com.airbridge.mirror.MirrorAccessibilityService"

    @Test fun enabledWhenPresent() {
        assertTrue(accessibilityServiceEnabled("a/b:$comp:c/d", comp))
    }
    @Test fun enabledWhenOnlyOne() {
        assertTrue(accessibilityServiceEnabled(comp, comp))
    }
    @Test fun disabledWhenAbsent() {
        assertFalse(accessibilityServiceEnabled("a/b:c/d", comp))
    }
    @Test fun disabledWhenNull() {
        assertFalse(accessibilityServiceEnabled(null, comp))
    }
    @Test fun disabledWhenEmpty() {
        assertFalse(accessibilityServiceEnabled("", comp))
    }
}
```

- [ ] **Step 2: Run, verify FAIL:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.mirror.AccessibilityStatusTest"`

- [ ] **Step 3: Create** `AccessibilityStatus.kt`:
```kotlin
package com.airbridge.mirror

/** Czy `component` (pakiet/usługa) jest na liście włączonych usług dostępności
 *  (Settings.Secure "enabled_accessibility_services", rozdzielona ":"). */
fun accessibilityServiceEnabled(enabledServices: String?, component: String): Boolean {
    if (enabledServices.isNullOrEmpty()) return false
    return enabledServices.split(":").any { it.equals(component, ignoreCase = true) }
}
```

- [ ] **Step 4: Run, verify PASS (5 tests).** Same command as Step 2.

- [ ] **Step 5: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/mirror/AccessibilityStatus.kt android/Airbridge/app/src/test/java/com/airbridge/mirror/AccessibilityStatusTest.kt
git commit -m "feat(android): pure accessibilityServiceEnabled helper"
```

---

## Task 2: Android — wiersz Accessibility + podział wymagane/opcjonalne

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt`
- Modify: `android/.../res/values/strings.xml`, `values-pl/strings.xml`

- [ ] **Step 1: Add strings.** `values/strings.xml` (po `onboarding_perm_notiflistener_why`):
```xml
    <string name="onboarding_perm_accessibility_desc">Control from your Mac</string>
    <string name="onboarding_perm_accessibility_why">So you can control your phone from your Mac when mirroring (taps, typing). Optional — only needed for remote control</string>
    <string name="onboarding_perm_optional_header">Optional — mirroring &amp; Mac notifications</string>
```
`values-pl/strings.xml` (po polskim odpowiedniku):
```xml
    <string name="onboarding_perm_accessibility_desc">Sterowanie z Maca</string>
    <string name="onboarding_perm_accessibility_why">Aby sterować telefonem z Maca podczas mirrora (dotyk, pisanie). Opcjonalne — tylko do zdalnego sterowania</string>
    <string name="onboarding_perm_optional_header">Dodatkowe — mirror i powiadomienia na Macu</string>
```

- [ ] **Step 2: Add accessibility helper for the screen.** In `OnboardingScreen.kt`, add a top-level helper that reads the system setting and delegates to the pure function:
```kotlin
fun isMirrorAccessibilityEnabled(context: android.content.Context): Boolean {
    val flat = android.provider.Settings.Secure.getString(
        context.contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
    )
    val comp = "${context.packageName}/${context.packageName}.mirror.MirrorAccessibilityService"
    return com.airbridge.mirror.accessibilityServiceEnabled(flat, comp)
}
```

- [ ] **Step 3: Add state + launcher** in `PermissionsPage` (next to `notifListenerGranted`):
```kotlin
    var accessibilityGranted by remember { mutableStateOf(isMirrorAccessibilityEnabled(context)) }
    val accessibilityLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        accessibilityGranted = isMirrorAccessibilityEnabled(context)
    }
```

- [ ] **Step 4: Add optional-section header + accessibility row.** Find where the optional rows begin (the overlay `PermissionRow`). Insert a header `Text` BEFORE the overlay row:
```kotlin
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = stringResource(R.string.onboarding_perm_optional_header),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))
```
Then after the notification-listener `PermissionRow`, add the accessibility row:
```kotlin
        PermissionRow(
            icon = Icons.Rounded.TouchApp,
            description = stringResource(R.string.onboarding_perm_accessibility_desc),
            why = stringResource(R.string.onboarding_perm_accessibility_why),
            granted = accessibilityGranted,
            onRequest = {
                accessibilityLauncher.launch(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        )
```
Add import `androidx.compose.material.icons.rounded.TouchApp` if missing. NOT part of `allGranted` (optional).

- [ ] **Step 5: Compile.** `cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt android/Airbridge/app/src/main/res/values/strings.xml android/Airbridge/app/src/main/res/values-pl/strings.xml
git commit -m "feat(android): accessibility permission row + required/optional split in onboarding"
```

---

## Task 3: Android — wzmianka o mirrorze + lepszy opis powiadomień

**Files:**
- Modify: `android/.../ui/OnboardingScreen.kt` (WelcomePage feature row)
- Modify: `android/.../res/values/strings.xml`, `values-pl/strings.xml`

- [ ] **Step 1: Add a mirror feature string + reword files feature.** `values/strings.xml`:
```xml
    <string name="onboarding_feature_mirror">Mirror your phone screen on your Mac — and back</string>
```
`values-pl/strings.xml`:
```xml
    <string name="onboarding_feature_mirror">Pokaż ekran telefonu na Macu — i odwrotnie</string>
```

- [ ] **Step 2: Add a FeatureRow on WelcomePage.** Find the 3 existing `FeatureRow` calls in `WelcomePage`; add a 4th:
```kotlin
        FeatureRow(
            icon = Icons.Rounded.ScreenShare,
            text = stringResource(R.string.onboarding_feature_mirror)
        )
```
Add import `androidx.compose.material.icons.rounded.ScreenShare` if missing (note: may be deprecated → use `Icons.AutoMirrored.Rounded.ScreenShare` + its import if compiler warns; pick whichever compiles cleanly).

- [ ] **Step 3: Compile.** `cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt android/Airbridge/app/src/main/res/values/strings.xml android/Airbridge/app/src/main/res/values-pl/strings.xml
git commit -m "feat(android): mention screen mirroring on onboarding welcome"
```

---

## Task 4: macOS — `NSScreenRecordingUsageDescription` w Info.plist

**Files:**
- Modify: `macos/Airbridge/Resources/Info.plist`

- [ ] **Step 1: Add the key.** Inside the top-level `<dict>`, next to `NSLocalNetworkUsageDescription`:
```xml
    <key>NSScreenRecordingUsageDescription</key>
    <string>AirBridge needs screen recording to show your Mac's screen on your phone (reverse mirroring).</string>
```

- [ ] **Step 2: Build.** `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit:**
```bash
git add macos/Airbridge/Resources/Info.plist
git commit -m "feat(macos): NSScreenRecordingUsageDescription for reverse mirror"
```

---

## Task 5: macOS — strona uprawnień w onboardingu

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/OnboardingView.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` (wstrzyknięcie serwisów do OnboardingView)

- [ ] **Step 1: Inject services into OnboardingView.** READ `OnboardingView` — it has `pairingService`, `connectionService`, `onComplete`. Add `let hotkeyService: GlobalHotkeyService` and `let notificationService: NotificationService`. In `AirbridgeApp.swift` find the `OnboardingView(...)` call (in the `else` branch of `onboardingCompleted`) and pass `hotkeyService: hotkeyService, notificationService: notificationService`.

- [ ] **Step 2: Add permission state + the page.** In `OnboardingView`, add state:
```swift
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var notificationsAuthorized = false
    @State private var accessibilityPollTimer: Timer?
```
Add the `permissionsPage` computed view (style consistent with `howItWorksPage` — icon, title, rows). Each row: title, short "why", `StatusIndicator` + a "Grant"/"Przyznaj" button when not granted:
```swift
    private var permissionsPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 56)).foregroundStyle(.tint)
                .symbolEffect(.bounce, value: page)
            Text(isPL ? "Uprawnienia" : "Permissions")
                .font(.ab(.title)).fontWeight(.bold)
            Text(isPL ? "Wszystkie opcjonalne poza siecią — możesz pominąć i wrócić w Ustawieniach."
                      : "All optional except network — you can skip and return in Settings.")
                .font(.ab(.subheadline)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            permissionRow(
                title: isPL ? "Powiadomienia" : "Notifications",
                why: isPL ? "Powiadomienia z telefonu na Macu" : "Phone notifications on your Mac",
                granted: notificationsAuthorized,
                grant: {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                        refreshNotificationStatus()
                    }
                })
            permissionRow(
                title: isPL ? "Dostępność" : "Accessibility",
                why: isPL ? "Skrót Quick Drop i sterowanie telefonem" : "Quick Drop shortcut & controlling your phone",
                granted: accessibilityGranted,
                grant: {
                    hotkeyService.requestAccessibilityAndStart()
                    startAccessibilityPolling()
                })
            permissionRow(
                title: isPL ? "Nagrywanie ekranu" : "Screen recording",
                why: isPL ? "Pokazywanie ekranu Maca na telefonie" : "Show your Mac's screen on your phone",
                granted: screenRecordingGranted,
                grant: {
                    _ = CGRequestScreenCaptureAccess()
                    screenRecordingGranted = CGPreflightScreenCaptureAccess()
                })
            permissionRow(
                title: isPL ? "Sieć lokalna" : "Local network",
                why: isPL ? "Wykrywanie telefonu w Wi-Fi (systemowo przy 1. połączeniu)" : "Discover your phone on Wi-Fi (granted on first connect)",
                granted: true,
                grant: nil)
        }
        .padding(.horizontal, 40)
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, why: String, granted: Bool, grant: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ab(.body)).fontWeight(.medium)
                Text(why).font(.ab(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            StatusIndicator(state: granted ? .connected : .error, size: 12)
            if !granted, let grant {
                Button(isPL ? "Przyznaj" : "Grant", action: grant)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if AXIsProcessTrusted() {
                accessibilityGranted = true
                accessibilityPollTimer?.invalidate()
                accessibilityPollTimer = nil
            }
        }
    }
```
Add imports at top: `import UserNotifications`, `import CoreGraphics` (CG screen-capture), and `import ApplicationServices` (AXIsProcessTrusted) if not already available. `StatusIndicator` is an existing component (used in SettingsView) — confirm it's accessible from this module.

- [ ] **Step 3: Wire the page into the pager (3 → 4 pages).** Update the `switch page` to insert `permissionsPage` as `case 2` and move the pairing page to `case 3` (default). Update the bottom-bar navigation: the "Next" condition `page < 2` becomes `page < 3`; the dot-indicator count `0..<3` becomes `0..<4`; the pairing/skip controls trigger at `page == 3` instead of `2`. READ the nav section (lines ~57-130) and bump every `2` that means "last page index" to `3`, and every `3` that means "page count" to `4`.

- [ ] **Step 4: Build.** `cd macos/Airbridge && swift build`
Expected: Build complete. (Ignore SourceKit "No such module" false positives.)

- [ ] **Step 5: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/OnboardingView.swift macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift
git commit -m "feat(macos): permissions page in onboarding (notifications, accessibility, screen recording, network)"
```

---

## Task 6: Weryfikacja (build + ręczna e2e)

- [ ] **Step 1: Tests + builds.**
```bash
cd android/Airbridge && ./gradlew :app:testDebugUnitTest && ./gradlew :app:assembleDebug
cd ../../macos/Airbridge && swift build
```
Expected: wszystko zielone (Mirror integration pre-existing fail unrelated).

- [ ] **Step 2: Install/run.** Android install APK; macOS `scripts/dev-install.sh`.

- [ ] **Step 3: Manual e2e.**
  - Android: w `PermissionsPage` widać sekcję „Dodatkowe" z overlay, accessibility, notification-listener; wiersz „Sterowanie z Maca" otwiera ekran Accessibility i po włączeniu pokazuje ✓; sekcja wymaganych dalej steruje `allGranted`. WelcomePage wspomina mirror.
  - macOS: w onboardingu (reset onboardingu lub świeży profil) nowa strona „Uprawnienia" — każdy przycisk „Przyznaj" wyzwala systemowy prompt; status odświeża się (accessibility przez polling, screen recording/notifications po powrocie); „Pomiń"/„Dalej" działają; sieć lokalna = info.
  - macOS reverse mirror: po przyznaniu Screen Recording z wizarda — „Pokaż ekran" działa bez dodatkowego proszenia.

- [ ] **Step 4: Commit ewentualnych poprawek.**

---

## Self-Review

- **Spec coverage:** Android accessibility row + helper + czysta funkcja+test (Task 1,2) ✓; podział wymagane/opcjonalne (Task 2 Step 4) ✓; mirror w feature + opisy (Task 3) ✓; macOS strona uprawnień: powiadomienia/accessibility/screen-recording/sieć z grant+status (Task 5) ✓; Info.plist screen recording (Task 4) ✓; wstrzyknięcie serwisów (Task 5 Step 1) ✓.
- **Type consistency:** `accessibilityServiceEnabled(enabledServices, component)` (Task 1↔2); `isMirrorAccessibilityEnabled(context)` (Task 2); macOS `permissionRow(title:why:granted:grant:)`, `refreshNotificationStatus`, `startAccessibilityPolling`, state names (Task 5 wewnętrznie spójne); `hotkeyService.requestAccessibilityAndStart()` (istniejące, z SettingsView).
- **Placeholders:** UI/integracyjne kroki (nav bump, AirbridgeApp call, OnboardingView injection) instruują „READ + adapt" z konkretnymi liczbami/nazwami; czysta funkcja + stringi mają pełny kod.
- **Uwaga:** Task 1 ścieżka — plik w `mirror/` (accessibility dotyczy MirrorAccessibilityService), nie `notification/`.
