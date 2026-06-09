# Material 3 Expressive Refresh (Android) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt Material 3 Expressive in the Android app: expressive theme + motion, wavy transfer progress, morphing loading indicators, connected button group for theme picker, FAB menu for send actions, expressive icon-container shapes, and removal of the hardcoded green.

**Architecture:** Pure UI-layer changes in Jetpack Compose. No service/network logic is touched. A single global compiler opt-in (`ExperimentalMaterial3ExpressiveApi`) avoids per-file `@OptIn` annotations.

**AMENDMENT (executed during Task 2):** material3 1.4.0 from BOM 2025.12.00 does NOT ship the expressive components (only design tokens; `MaterialExpressiveTheme` is internal). The dependency was bumped to `androidx.compose.material3:material3:1.5.0-alpha14` — the newest alpha compatible with AGP 8.6.1 (alpha15+ pulls compose ui 1.11/1.12 requiring AGP ≥ 9). Verified in the alpha14 AAR: LoadingIndicator, WavyProgressIndicator, ButtonGroup(+Defaults), FloatingActionButtonMenu, MaterialShapes, ToggleButton all present; `MotionScheme.expressive()` public. Commit `e399571`.

**Tech Stack:** Kotlin 2.0, Jetpack Compose, Material 3 (BOM 2025.12.00), Gradle (`./gradlew` from `android/Airbridge`).

---

## CRITICAL: Repository hygiene

The working tree contains **uncommitted reconnect WIP** that must NOT be committed by this plan:

- `android/Airbridge/app/src/main/java/com/airbridge/discovery/NsdDiscovery.kt`
- `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt`
- `android/Airbridge/app/src/main/java/com/airbridge/service/WebSocketClient.kt`
- `android/Airbridge/app/src/main/res/drawable/ic_notification.xml`
- `android/Airbridge/app/src/main/java/com/airbridge/network/` (new)
- `android/Airbridge/app/src/main/java/com/airbridge/service/ReconnectPolicy.kt` (new)
- `android/Airbridge/app/src/test/java/com/airbridge/service/ReconnectPolicyTest.kt` (new)
- `macos/Airbridge/Sources/AirbridgeApp/Services/NetworkChangeMonitor.swift` (new)
- `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift`

**Every commit in this plan must `git add` ONLY the exact files listed in its task.** Never `git add -A` or `git add .`.

## Verification model

These are visual UI changes with no unit-testable logic (no new algorithms, no state machines). Verification per task = compile check; final task = full build + install on the phone for the user's visual test. Compile check command (run from `android/Airbridge`):

```bash
cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin
```

Expected: `BUILD SUCCESSFUL`. Warnings are acceptable; errors are not.

Commit messages in English (public repo), conventional-commit style, each ending with:

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

---

### Task 1: Global opt-in for expressive APIs

**Files:**
- Modify: `android/Airbridge/app/build.gradle.kts:38`

- [ ] **Step 1: Add compiler opt-in**

Replace:

```kotlin
    kotlinOptions { jvmTarget = "17" }
```

with:

```kotlin
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs += "-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi"
    }
```

- [ ] **Step 2: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL (an "unknown opt-in marker" *warning* would mean the annotation lives elsewhere — in that case check `androidx.compose.material3.ExperimentalMaterial3ExpressiveApi` actually exists in the BOM and fix the FQN; do not ignore it, later tasks depend on it).

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/build.gradle.kts
git commit -m "build(android): opt in to Material 3 Expressive APIs"
```

---

### Task 2: Expressive theme + semantic success color

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/Theme.kt`

- [ ] **Step 1: Switch to MaterialExpressiveTheme and add `ColorScheme.success`**

In `Theme.kt`:

(a) Add imports (keep existing ones):

```kotlin
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
```

(b) Replace the final `MaterialTheme(...)` call (lines 118–122):

```kotlin
    MaterialTheme(
        colorScheme = colorScheme,
        typography = AirbridgeTypography,
        content = content
    )
```

with:

```kotlin
    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        typography = AirbridgeTypography,
        content = content
    )
```

(`MaterialExpressiveTheme` defaults `motionScheme` to the expressive spring-based scheme — do not pass one explicitly.)

(c) Append at the end of the file a semantic success color (replaces hardcoded `0xFF4CAF50` across the app; variant picked off scheme luminance so it works for dynamic color and both theme modes):

```kotlin
// Semantyczny kolor "sukcesu" (np. przyznane uprawnienia) — M3 nie ma go w ColorScheme.
val ColorScheme.success: Color
    get() = if (surface.luminance() < 0.5f) Color(0xFF81C784) else Color(0xFF2E7D32)
```

- [ ] **Step 2: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/Theme.kt
git commit -m "feat(android): adopt MaterialExpressiveTheme with expressive motion"
```

---

### Task 3: Replace hardcoded green with `colorScheme.success`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt` (lines 430, 567, 574, 602, 616)

- [ ] **Step 1: Replace all five occurrences**

In `OnboardingScreen.kt` replace every `Color(0xFF4CAF50)` with `MaterialTheme.colorScheme.success` (all five sites are inside `@Composable` functions; `MaterialTheme` is already imported). Exact replacements:

Line 430: `tint = if (allGranted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary`
→ `tint = if (allGranted) MaterialTheme.colorScheme.success else MaterialTheme.colorScheme.primary`

Line 567: `tint = Color(0xFF4CAF50),` → `tint = MaterialTheme.colorScheme.success,`

Line 574: `color = Color(0xFF4CAF50),` → `color = MaterialTheme.colorScheme.success,`

Line 602: `tint = if (granted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.onSurfaceVariant`
→ `tint = if (granted) MaterialTheme.colorScheme.success else MaterialTheme.colorScheme.onSurfaceVariant`

Line 616: `tint = Color(0xFF4CAF50),` → `tint = MaterialTheme.colorScheme.success,`

Then verify with: `grep -n "4CAF50" android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt` — expected: no matches. If the `Color` import becomes unused, remove it only if nothing else in the file uses `Color(` (check first — Canvas drawing code in this file likely uses it; leave the import if so).

- [ ] **Step 2: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt
git commit -m "refactor(android): replace hardcoded green with semantic success color"
```

---

### Task 4: Wavy progress indicator for file transfer

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt:249-257`

Note: the resource bars in `MacMonitorCard.kt` deliberately stay flat (`LinearProgressIndicator`) — a wave implies ongoing activity, which fits a transfer but not a static CPU/RAM level.

- [ ] **Step 1: Replace the transfer LinearProgressIndicator**

In `MainScreen.kt` add import:

```kotlin
import androidx.compose.material3.LinearWavyProgressIndicator
```

Replace (lines 249–257):

```kotlin
                    LinearProgressIndicator(
                        progress = { transferProgress ?: 0f },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.15f)
                    )
```

with:

```kotlin
                    LinearWavyProgressIndicator(
                        progress = { transferProgress ?: 0f },
                        modifier = Modifier.fillMaxWidth(),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.15f)
                    )
```

(The wavy indicator draws its own stroke height/amplitude; default `amplitude` lambda flattens the wave near 100% — keep defaults.) If `LinearProgressIndicator` is no longer referenced anywhere in `MainScreen.kt`, remove its import (line 44). Keep the `CircularProgressIndicator` import for now — Task 5 removes it.

- [ ] **Step 2: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt
git commit -m "feat(android): wavy progress indicator for file transfers"
```

---

### Task 5: Morphing LoadingIndicator for connecting states

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt:355-358, 517-521`
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/PairingSuccessScreen.kt:89-93`

- [ ] **Step 1: MainScreen — ConnectingCard**

Add import to `MainScreen.kt`:

```kotlin
import androidx.compose.material3.LoadingIndicator
```

Replace in `ConnectingCard` (lines 355–358):

```kotlin
            CircularProgressIndicator(
                modifier = Modifier.size(48.dp),
                strokeWidth = 4.dp
            )
```

with:

```kotlin
            LoadingIndicator(
                modifier = Modifier.size(64.dp)
            )
```

- [ ] **Step 2: MainScreen — connect/disconnect transition (lines 517–521)**

Replace:

```kotlin
                            CircularProgressIndicator(
                                modifier = Modifier.size(36.dp),
                                color = MaterialTheme.colorScheme.primary,
                                strokeWidth = 3.dp
                            )
```

with:

```kotlin
                            LoadingIndicator(
                                modifier = Modifier.size(56.dp),
                                color = MaterialTheme.colorScheme.primary
                            )
```

Remove the now-unused `CircularProgressIndicator` import from `MainScreen.kt` (line 41).

- [ ] **Step 3: PairingSuccessScreen — pairing phase**

In `PairingSuccessScreen.kt` replace import `androidx.compose.material3.CircularProgressIndicator` (line 24) with `androidx.compose.material3.LoadingIndicator`, then replace (lines 89–93):

```kotlin
                    CircularProgressIndicator(
                        modifier = Modifier.size(48.dp),
                        color = MaterialTheme.colorScheme.primary,
                        strokeWidth = 4.dp
                    )
```

with:

```kotlin
                    LoadingIndicator(
                        modifier = Modifier.size(72.dp),
                        color = MaterialTheme.colorScheme.primary
                    )
```

- [ ] **Step 4: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt android/Airbridge/app/src/main/java/com/airbridge/ui/PairingSuccessScreen.kt
git commit -m "feat(android): morphing LoadingIndicator for connecting states"
```

---

### Task 6: Connected ButtonGroup for the theme picker

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/SettingsScreen.kt:152-188` (plus imports at lines 22–23)

- [ ] **Step 1: Replace radio list with a connected single-select group**

In `SettingsScreen.kt` remove imports `androidx.compose.material3.RadioButton` and `androidx.compose.material3.RadioButtonDefaults` (lines 22–23) and add:

```kotlin
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.ToggleButton
```

(If `Arrangement` is already imported, skip that line.)

Replace lines 152–188 (`val themeOptions = ...` through the end of `themeOptions.forEach { ... }` block):

```kotlin
                    val themeOptions = listOf(
                        "system" to stringResource(R.string.settings_theme_system),
                        "light" to stringResource(R.string.settings_theme_light),
                        "dark" to stringResource(R.string.settings_theme_dark)
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)
                    ) {
                        themeOptions.forEachIndexed { index, (value, label) ->
                            ToggleButton(
                                checked = themeMode == value,
                                onCheckedChange = {
                                    themeMode = value
                                    prefs.edit().putString("theme_mode", value).apply()
                                    onThemeChanged(value)
                                },
                                modifier = Modifier.weight(1f),
                                shapes = when (index) {
                                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                                    themeOptions.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                                }
                            ) {
                                Text(label, maxLines = 1)
                            }
                        }
                    }
```

`Row`, `Modifier`, `Text`, `stringResource` are already imported. If destructuring `(value, label)` in `forEachIndexed` fails to compile, use `themeOptions.forEachIndexed { index, option -> val (value, label) = option ... }`.

- [ ] **Step 2: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/SettingsScreen.kt
git commit -m "feat(android): connected button group for theme picker"
```

---

### Task 7: FAB menu replaces the send bottom sheet

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/MainActivity.kt`

The centered FAB currently opens a `ModalBottomSheet` with three `SendOption` rows. Replace with an expressive `FloatingActionButtonMenu` anchored at the same spot (centered over the nav bar). The file-confirmation `ModalBottomSheet` (`pendingFileUri`) STAYS — only the send-options sheet goes away. The "Send" caption under the FAB is dropped (menu items carry labels).

- [ ] **Step 1: Imports**

In `MainActivity.kt` add:

```kotlin
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.runtime.derivedStateOf
```

Remove imports that become unused after the steps below: `androidx.compose.material3.ModalBottomSheet` ONLY IF the confirmation sheet were also removed — it is NOT, so keep it. After finishing the task run a check for genuinely unused imports (`FloatingActionButton`, `FloatingActionButtonDefaults`, `rememberModalBottomSheetState` stays — confirmation sheet uses it).

- [ ] **Step 2: Rename state**

Replace `var showSendSheet by remember { mutableStateOf(false) }` (line 143) with:

```kotlin
                    var fabMenuExpanded by remember { mutableStateOf(false) }
```

- [ ] **Step 3: Strip the FAB from the bottom bar**

In the `Scaffold` `bottomBar`, the middle placeholder `NavigationBarItem` (lines 195–201): change `onClick = { showSendSheet = true }` to `onClick = { }` (it is `enabled = false` anyway). Then DELETE the whole `Column` containing the `FloatingActionButton` + "Send" `Text` (lines 220–261, the block starting `// FAB centered over the bar`). The wrapping `Box { NavigationBar { ... } }` can stay a plain `Box` or be unwrapped — leave the `Box` (smaller diff).

- [ ] **Step 4: Wrap Scaffold in a Box and add the FAB menu overlay**

Wrap the existing `Scaffold(...) { innerPadding -> ... }` call in:

```kotlin
                    Box(modifier = Modifier.fillMaxSize()) {
                        Scaffold(
                            // ... unchanged ...
                        ) { innerPadding ->
                            // ... unchanged HorizontalPager ...
                        }

                        FloatingActionButtonMenu(
                            expanded = fabMenuExpanded,
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .navigationBarsPadding()
                                .padding(bottom = 20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            button = {
                                ToggleFloatingActionButton(
                                    checked = fabMenuExpanded,
                                    onCheckedChange = { if (hasPairedDevices) fabMenuExpanded = it }
                                ) {
                                    val icon by remember {
                                        derivedStateOf {
                                            if (checkedProgress > 0.5f) Icons.Rounded.Close
                                            else Icons.Rounded.FileUpload
                                        }
                                    }
                                    Icon(
                                        icon,
                                        contentDescription = stringResource(R.string.nav_send)
                                    )
                                }
                            }
                        ) {
                            FloatingActionButtonMenuItem(
                                onClick = {
                                    fabMenuExpanded = false
                                    filePickerLauncher.launch(arrayOf("*/*"))
                                },
                                icon = { Icon(Icons.AutoMirrored.Rounded.InsertDriveFile, contentDescription = null) },
                                text = { Text(stringResource(R.string.action_send_file)) }
                            )
                            FloatingActionButtonMenuItem(
                                onClick = {
                                    fabMenuExpanded = false
                                    photoPickerLauncher.launch(
                                        ActivityResultContracts.PickVisualMedia
                                            .ImageAndVideo.let {
                                                androidx.activity.result.PickVisualMediaRequest(it)
                                            }
                                    )
                                },
                                icon = { Icon(Icons.Rounded.Photo, contentDescription = null) },
                                text = { Text(stringResource(R.string.action_send_photo)) }
                            )
                            FloatingActionButtonMenuItem(
                                onClick = {
                                    fabMenuExpanded = false
                                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = clipboard.primaryClip
                                    if (clip != null && clip.itemCount > 0) {
                                        val text = clip.getItemAt(0).coerceToText(context).toString()
                                        if (text.isNotEmpty()) {
                                            viewModel.sendClipboard(text)
                                            Toast.makeText(context, context.getString(R.string.sent_to_mac), Toast.LENGTH_SHORT).show()
                                        } else {
                                            Toast.makeText(context, context.getString(R.string.clipboard_empty), Toast.LENGTH_SHORT).show()
                                        }
                                    } else {
                                        Toast.makeText(context, context.getString(R.string.clipboard_empty), Toast.LENGTH_SHORT).show()
                                    }
                                },
                                icon = { Icon(Icons.Rounded.ContentPaste, contentDescription = null) },
                                text = { Text(stringResource(R.string.action_send_clipboard)) }
                            )
                        }
                    }
```

API notes for the executor:
- `checkedProgress` is a property of `ToggleFloatingActionButtonScope` (the content lambda receiver) — if the compiler can't resolve it, check the scope type in the BOM and adapt (a static `if (fabMenuExpanded)` icon swap is an acceptable fallback).
- `ToggleFloatingActionButton` may require its content `Icon` to be tinted for contrast; if the icon is invisible, set `tint = MaterialTheme.colorScheme.onPrimaryContainer` or use the `Modifier.animateIcon`/checkedProgress-based color from the official sample.
- If `FloatingActionButtonMenu` has no `horizontalAlignment` parameter in this BOM version, drop that argument (items will right-align; acceptable).

- [ ] **Step 5: Delete the send ModalBottomSheet and SendOption**

Delete the whole `if (showSendSheet) { ModalBottomSheet(...) { ... } }` block (lines 283–353) and the now-unused private `SendOption` composable (lines 542–577). The `pendingFileUri` confirmation `ModalBottomSheet` block STAYS.

- [ ] **Step 6: Compile check + unused-import sweep**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL. Remove imports the compiler/warnings flag as unused (likely `FloatingActionButton`, `FloatingActionButtonDefaults`, `CircleShape` if nothing else uses it — `SendConfirmationSheet` DOES use `CircleShape`, so it stays).

- [ ] **Step 7: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/MainActivity.kt
git commit -m "feat(android): expressive FAB menu replaces send bottom sheet"
```

---

### Task 8: Expressive MaterialShapes for hero icon containers

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt` (hero containers at lines ~262, ~421, ~745, ~785)
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/PairingSuccessScreen.kt` (lines ~84, ~118)

Only the large 140dp hero containers change; small 40–48dp circles (avatar dots, list icons) stay `CircleShape`.

- [ ] **Step 1: OnboardingScreen**

Add imports:

```kotlin
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.toShape
```

(If `toShape` is unresolved in `androidx.compose.material3`, try `androidx.graphics.shapes` / check where the extension lives in this BOM.)

Replace `.clip(CircleShape)` on the four 140dp hero `Box`es:
- line ~262 (welcome page hero): `.clip(MaterialShapes.Cookie12Sided.toShape())`
- line ~421 (permissions hero): `.clip(MaterialShapes.Clover8Leaf.toShape())`
- line ~745 (how-it-works symbol 1): `.clip(MaterialShapes.Cookie9Sided.toShape())`
- line ~785 (how-it-works symbol 2): `.clip(MaterialShapes.Sunny.toShape())`

Leave lines ~688 and ~717 (`CircleShape` on small elements) untouched.

- [ ] **Step 2: PairingSuccessScreen**

Add the same two imports. Replace `.clip(CircleShape)`:
- line ~85 (pairing-in-progress hero): `.clip(MaterialShapes.Cookie12Sided.toShape())`
- line ~120 (success hero): `.clip(MaterialShapes.Sunny.toShape())`

If `CircleShape` becomes unused in `PairingSuccessScreen.kt`, remove its import.

- [ ] **Step 3: Compile check**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
cd /Users/marcinbaszewski/Projekty/airbridge
git add android/Airbridge/app/src/main/java/com/airbridge/ui/OnboardingScreen.kt android/Airbridge/app/src/main/java/com/airbridge/ui/PairingSuccessScreen.kt
git commit -m "feat(android): expressive MaterialShapes for hero icon containers"
```

---

### Task 9: Full build, unit tests, install on phone

**Files:** none (verification only)

- [ ] **Step 1: Unit tests (guard against accidental logic changes)**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL, all tests pass (includes ReconnectPolicyTest from the WIP — it must still pass).

- [ ] **Step 2: Full debug build + install on the connected phone**

Run: `cd /Users/marcinbaszewski/Projekty/airbridge/android/Airbridge && ./gradlew installDebug`
Expected: BUILD SUCCESSFUL, `Installing APK ... on device`. If no device is connected, report it and stop — do NOT try to work around it.

- [ ] **Step 3: Report for visual test**

Tell the user what to look at (in Polish): płynniejsze sprężynowe animacje w całej apce, falujący pasek postępu przy transferze, morfujący loader przy łączeniu, połączona grupa przycisków w wyborze motywu, FAB rozwijany w menu Wyślij, ekspresyjne kształty ikon w onboardingu/parowaniu. Do not run extra adb diagnostics — let the user click around.
