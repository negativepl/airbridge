# Android M3 Expressive Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Przejść Android UI na natywny Material 3 Expressive — dynamic color (Material You z tapety), `MaterialExpressiveTheme`, expressive motion + dedykowane animacje przejść; usunąć custom paletę ametyst/róż.

**Architecture:** Bump `compose-bom` do wersji z `material3` 1.4 (Expressive API), potem przerobić `Theme.kt` na `MaterialExpressiveTheme` z dynamic color i `MotionScheme.expressive()`, dołożyć punktowe animacje w `MainScreen`. Ekrany dziedziczą motyw automatycznie — nie wymagają zmian.

**Tech Stack:** Kotlin, Jetpack Compose, Material 3 Expressive (`material3` 1.4+), Gradle. Weryfikacja: `./gradlew :app:assembleDebug` + `:app:testDebugUnitTest` + ręczna e2e (motyw to UI — brak testów jednostkowych dla samego wyglądu).

---

## Ważne uwagi dla wykonawcy

- **Task 1 (bump) jest eksploracyjny.** Nie da się z góry wypisać wszystkich breaking changes po podniesieniu BOM. Proces: zmień wersję → zbuduj → napraw błędy pojedynczo → powtarzaj aż zielone. Jeśli utkniesz na niejasnym błędzie API — raportuj `BLOCKED` z treścią błędu, nie zgaduj w kółko.
- Motyw i animacje to zmiany wizualne — weryfikacja przez build + uruchomienie, nie testy jednostkowe. Istniejące testy mają dalej przechodzić.
- Nie dotykać macOS. Nie przeprojektowywać układów ekranów (tylko motyw/kolory/animacje).

---

## Task 1: Bump compose-bom do material3 1.4 (Expressive API)

**Files:**
- Modify: `android/Airbridge/app/build.gradle.kts` (linia ~43: `compose-bom`), ewentualnie `android/Airbridge/gradle/libs.versions.toml` jeśli wersje tam.

- [ ] **Step 1: Znajdź najnowszy stabilny compose-bom z material3 ≥ 1.4.0.**
Material 3 Expressive (`MaterialExpressiveTheme`, `MotionScheme.expressive()`, `expressiveLightColorScheme()`) jest w `androidx.compose.material3:material3` 1.4.0+. Ustal wersję BOM, która go zawiera (compose-bom z 2025; zacznij od najnowszego stabilnego, np. `2025.10.01`, i jeśli nie ma 1.4 — podnoś). Zmień w `app/build.gradle.kts`:
```kotlin
implementation(platform("androidx.compose:compose-bom:<WERSJA>"))
```

- [ ] **Step 2: Zbuduj — wykryj breaking changes.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Możliwe: niezgodność Kotlin / compose-compiler / AGP z nowym BOM. Jeśli build zgłasza wymóg nowszego Kotlina lub compilera — podnieś odpowiednie wersje (`kotlin`, `kotlinCompilerExtensionVersion` lub plugin `org.jetbrains.kotlin.plugin.compose`) do zgodnych z wybranym Compose. Czytaj komunikaty błędów dosłownie.

- [ ] **Step 3: Napraw błędy kompilacji pojedynczo.**
Typowe po bumpie material3: zmienione/zdeprecowane sygnatury (np. `LinearProgressIndicator(progress = {…})`, `ProgressIndicator`, `Divider`→`HorizontalDivider`). Dla KAŻDEGO błędu: zastosuj minimalną poprawkę zgodną z nowym API, przebuduj. Nie zmieniaj logiki ani wyglądu — tylko dostosuj wywołania do nowego API.

- [ ] **Step 4: Build zielony + istniejące testy.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL, testy przechodzą.

- [ ] **Step 5: Commit.**
```bash
git add android/Airbridge/app/build.gradle.kts android/Airbridge/gradle/libs.versions.toml
git commit -m "build(android): bump compose-bom to material3 1.4 (Expressive API)"
```
(Dodaj tylko realnie zmienione pliki; jeśli `libs.versions.toml` nietknięty — pomiń.)

---

## Task 2: Theme.kt → MaterialExpressiveTheme + dynamic color + expressive motion

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/Theme.kt`

- [ ] **Step 1: Zastąp funkcję `AirbridgeTheme`** (linie ~207-245) wersją expressive z dynamic color i natywnym fallbackiem:

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AirbridgeTheme(
    themeMode: String = "system",
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> isSystemInDarkTheme()
    }

    val context = LocalContext.current
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> darkColorScheme()
        else -> expressiveLightColorScheme()
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.surface.toArgb()
            window.navigationBarColor = colorScheme.surfaceContainer.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        typography = AirbridgeTypography,
        motionScheme = MotionScheme.expressive(),
        content = content
    )
}
```

Uwaga: zweryfikuj sygnaturę `MaterialExpressiveTheme` w użytej wersji (parametry `colorScheme`, `motionScheme`, `typography`, `shapes`, `content`). Jeśli `shapes` jest parametrem — NIE przekazuj `AirbridgeShapes` (chcemy natywne expressive kształty). Jeśli `motionScheme` ma inną nazwę/typ — dostosuj do faktycznego API (cel: expressive motion).

- [ ] **Step 2: Usuń custom palety i statyczne schematy.**
Usuń z `Theme.kt` cały blok prywatnych kolorów `Amethyst*`, `Lavender*`, `Mauve*`, `Error*` ORAZ definicje `private val LightColorScheme = lightColorScheme(...)` i `private val DarkColorScheme = darkColorScheme(...)` (oparte na nich). Usuń też `private val AirbridgeShapes` jeśli po Step 1 nie jest już używany. Zostaw `AirbridgeTypography`.

- [ ] **Step 3: Popraw importy.**
Dodaj: `androidx.compose.material3.MaterialExpressiveTheme`, `androidx.compose.material3.ExperimentalMaterial3ExpressiveApi`, `androidx.compose.material3.MotionScheme`, `androidx.compose.material3.expressiveLightColorScheme`, `androidx.compose.material3.darkColorScheme`, `androidx.compose.material3.dynamicDarkColorScheme`, `androidx.compose.material3.dynamicLightColorScheme`.
Usuń nieużywane: `MaterialTheme` (jeśli już nieużywany w tym pliku), `lightColorScheme`, `Shapes` (jeśli AirbridgeShapes usunięty), import `RoundedCornerShape` jeśli zbędny.

- [ ] **Step 4: Build.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL. Jeśli `MaterialExpressiveTheme`/`MotionScheme`/`expressiveLightColorScheme` nierozpoznane → wersja material3 z Task 1 jest za niska; wróć do Task 1 i podnieś BOM. Zgłoś to.

- [ ] **Step 5: Commit.**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/ui/Theme.kt
git commit -m "feat(android): MaterialExpressiveTheme + dynamic color + expressive motion; drop custom amethyst palette"
```

---

## Task 3: Włącz dynamic color w miejscu wywołania motywu

**Files:**
- Modify: miejsce, które wywołuje `AirbridgeTheme { }` (zwykle `MainActivity` w `setContent`, lub root composable). Znajdź: `grep -rn "AirbridgeTheme(" android/Airbridge/app/src/main/java/`.

- [ ] **Step 1: Zlokalizuj wywołanie `AirbridgeTheme`.**
Run: `grep -rn "AirbridgeTheme(" android/Airbridge/app/src/main/java/`
Jeśli wywołanie przekazuje `dynamicColor = false` lub `themeMode` — odczytaj, jak teraz jest budowane (np. z DataStore/preferencji themeMode).

- [ ] **Step 2: Upewnij się, że `dynamicColor` jest włączony.**
Domyślny parametr w Task 2 to `dynamicColor = true`, więc jeśli wywołanie NIE przekazuje `dynamicColor` jawnie — nic nie trzeba (dziedziczy true). Jeśli przekazuje `dynamicColor = false` — usuń ten argument lub zmień na `true`. Zachowaj przekazywanie `themeMode` bez zmian.

- [ ] **Step 3: Build.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit (jeśli był jakikolwiek edit; inaczej pomiń).**
```bash
git add -A && git commit -m "feat(android): enable dynamic color at theme call site"
```

---

## Task 4: Dedykowane animacje przejść w MainScreen

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt`

- [ ] **Step 1: Owiń przełączanie stanu połączenia w expressive `AnimatedContent`.**
Obecnie (po wcześniejszej pracy) jest `when { isConnected && mac != null -> MacMonitorCard; isConnected -> ConnectingCard; else -> DeviceCard }`. Zamień ten `when` na `AnimatedContent` na trójstanowym kluczu, z przejściem fade+scale (spójnym z istniejącym `AnimatedContent` w `DeviceCard`):

```kotlin
val connState = when {
    isConnected && mac != null -> 2  // MacMonitorCard
    isConnected -> 1                 // ConnectingCard
    else -> 0                        // DeviceCard
}
androidx.compose.animation.AnimatedContent(
    targetState = connState,
    transitionSpec = {
        (androidx.compose.animation.fadeIn(animationSpec = androidx.compose.animation.core.tween(300)) +
         androidx.compose.animation.scaleIn(initialScale = 0.96f, animationSpec = androidx.compose.animation.core.tween(300)))
            .togetherWith(androidx.compose.animation.fadeOut(animationSpec = androidx.compose.animation.core.tween(200)))
    },
    label = "connectionState"
) { state ->
    when (state) {
        2 -> MacMonitorCard(info = mac!!, wallpaperBase64 = macWallpaper, onDisconnect = { viewModel.disconnect() })
        1 -> ConnectingCard(deviceName = connectedDeviceName)
        else -> DeviceCard(
            isConnected = isConnected,
            deviceName = connectedDeviceName,
            onDisconnect = { viewModel.disconnect() },
            onReconnect = { viewModel.reconnect() }
        )
    }
}
```
Uwaga: `mac!!` jest bezpieczne tylko w gałęzi `state == 2`; jeśli kompilator smart-cast marudzi (bo `mac` to `val` z `macInfo`), przechwyć wcześniej do lokalnej `val macLocal = mac` i użyj jej. Zachowaj istniejące wywołania/parametry komponentów dokładnie jak były.

- [ ] **Step 2: Animuj wstawianie/znikanie wierszy listy ostatnich transferów.**
Znajdź `LazyColumn`/`items(...)` renderujące ostatnie transfery (`grep -n "items(" MainScreen.kt`, szukaj listy transferów / `RecentTransferRow`). Na elemencie listy dodaj `Modifier.animateItem()` (Compose 1.7+ API; w nowym BOM dostępne). Przykład w bloku `items`:
```kotlin
RecentTransferRow(/* … */, modifier = Modifier.animateItem())
```
Jeśli `RecentTransferRow` nie przyjmuje `modifier` — owiń jego wywołanie w `Box(Modifier.animateItem()) { RecentTransferRow(...) }`. Jeśli nie ma listy transferów jako `LazyColumn items` (np. zwykła `Column`) — pomiń ten krok i odnotuj w raporcie (animateItem działa tylko w lazy listach).

- [ ] **Step 3: Build.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit.**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/ui/MainScreen.kt
git commit -m "feat(android): expressive animated transitions for connection state + transfer list"
```

---

## Task 5: Weryfikacja (build + ręczna e2e)

- [ ] **Step 1: Pełny build + testy.**
Run: `cd android/Airbridge && ./gradlew :app:assembleDebug && ./gradlew :app:testDebugUnitTest`
Expected: oba BUILD SUCCESSFUL.

- [ ] **Step 2: Instalacja + uruchomienie.**
Run: `adb -s 192.168.1.5:35519 install -r android/Airbridge/app/build/outputs/apk/debug/app-debug.apk` i relaunch.

- [ ] **Step 3: Scenariusze ręczne.**
  - Dynamic color: zmień tapetę telefonu (Android 12+) → kolory aplikacji podążają za tapetą; brak śladu starego fioletu/różu.
  - Tryb jasny/ciemny (Ustawienia → motyw system/jasny/ciemny) działa.
  - Animacje: rozłącz/połącz z Makiem → płynne expressive przejście DeviceCard → ConnectingCard → MacMonitorCard (bez przeskoków).
  - Lista ostatnich transferów: nowy transfer wsuwa się z animacją (jeśli lista to LazyColumn).
  - Przejrzyj główne ekrany (Onboarding, About, Settings, ScreenShare) — czytelność i kontrast na dynamic color, nic nie wygląda zepsute.

- [ ] **Step 4: Commit ewentualnych poprawek.**

---

## Self-Review

- **Spec coverage:** bump BOM do material3 1.4 (Task 1) ✓; MaterialExpressiveTheme + dynamic color + fallback expressive/dark + MotionScheme.expressive (Task 2) ✓; usunięcie custom palet (Task 2 Step 2) ✓; dynamic włączony (Task 3) ✓; dedykowane animacje przejść połączenia + lista (Task 4) ✓; ekrany bez zmian (dziedziczą motyw) ✓; weryfikacja jasny/ciemny/dynamic/animacje (Task 5) ✓.
- **Placeholder scan:** Task 1 i 3 są celowo procesowe (bump nieprzewidywalny, call-site nieznany do grep) — instruują dokładne komendy i kryteria, nie zostawiają „TODO". Reszta ma pełny kod.
- **Type/identifier consistency:** `AirbridgeTheme(themeMode, dynamicColor, content)`, `expressiveLightColorScheme()`/`darkColorScheme()` fallback, `MotionScheme.expressive()`, `MaterialExpressiveTheme` spójne między Task 2 a 3. `ConnectingCard`/`DeviceCard`/`MacMonitorCard` (z poprzedniej pracy, już w MainScreen) użyte w Task 4 z istniejącymi sygnaturami.
- **Ryzyko odnotowane:** bump (Task 1) może wymagać iteracji / eskalacji; jasno zaznaczone.
