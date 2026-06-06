# Android UI: redesign na Material 3 Expressive

**Data:** 2026-06-06
**Status:** zaakceptowany design
**Branch:** `feat/android-m3-expressive` (z czystego mastera, po zmergowaniu plików+ładowania)

## Cel

Odejść od narzuconej, custom palety ametyst/róż na rzecz **natywnego Material 3 Expressive**:
kolory z Material You (dynamic color z tapety telefonu) + wbudowany expressive motion +
dedykowane animacje na kluczowych przejściach. UI ma być natywne i spójne z systemem.

## Decyzje

- **Kolory: Dynamic Color / Material You.** Na Androidzie 12+ kolory generowane z tapety
  (`dynamicLightColorScheme` / `dynamicDarkColorScheme`); fallback na starszych:
  `expressiveLightColorScheme()` / `darkColorScheme()`. Koniec custom różu.
- **Motyw expressive:** `MaterialExpressiveTheme` (opt-in `@ExperimentalMaterial3ExpressiveApi`)
  z `motionScheme = MotionScheme.expressive()`.
- **Bump zależności konieczny:** Expressive API jest w `material3` 1.4 (2025); projekt ma
  `compose-bom` 2024.06. To największe ryzyko — bump może złamać kompilację; przechodzimy
  iteracyjnie, naprawiając błędy.

## 1. Zależności (`app/build.gradle.kts`, `gradle/libs.versions.toml`)

- `compose-bom` 2024.06.00 → najnowszy stabilny BOM zawierający `material3` 1.4.x
  (Expressive API). Jeśli BOM wymusza nowszy Kotlin / compose-compiler — też bump.
- Po bumpie: pełny build (`assembleDebug`) i naprawa ewentualnych breaking changes
  (deprecacje API, zmiany sygnatur). Każdy błąd kompilacji adresowany pojedynczo.

## 2. Motyw (`ui/Theme.kt`)

- `MaterialTheme { }` → `MaterialExpressiveTheme(colorScheme = …, motionScheme = MotionScheme.expressive()) { }`.
- Wybór schematu w `AirbridgeTheme(themeMode, content)`:
  - dark/light wg `themeMode` (system/light/dark — zachować, czyta z Ustawień);
  - jeśli Android 12+ (`SDK_INT >= S`): `dynamicDarkColorScheme(ctx)` / `dynamicLightColorScheme(ctx)`;
  - inaczej fallback: `darkColorScheme()` / `expressiveLightColorScheme()`.
- **Usunąć** cały blok custom palet `Amethyst*` / `Lavender*` / `Mauve*` i statyczne
  `LightColorScheme`/`DarkColorScheme` oparte na nich.
- Typografię (`AirbridgeTypography`) zachować. Kształty → expressive/M3 defaults (nie wymuszać
  custom `AirbridgeShapes`; pozwolić expressive theme nadać natywne, mocniej zaokrąglone kształty).
- Status/navigation bar: dalej z `colorScheme.surface` / `surfaceContainer` (jak teraz),
  ale kolory pochodzą już z dynamic scheme.

## 3. Dedykowane animacje (YAGNI — punktowo)

- Globalny expressive motion z tematu (komponenty M3 dziedziczą sprężyste przejścia automatycznie).
- Kluczowe przejścia stanu połączenia: `DeviceCard` ↔ `ConnectingCard` ↔ `MacMonitorCard` —
  expressive `AnimatedContent` (już jest `AnimatedContent` w `DeviceCard`; ujednolicić spec
  przejścia na expressive spring i objąć nim przełączanie na poziomie `MainScreen`).
- Lista „ostatnich transferów" — `animateItem()` dla wstawiania/usuwania wierszy.
- **Nie** animować wszystkiego — tylko powyższe hero-przejścia.

## 4. Co bez zmian

- Ekrany (Main, MacMonitor, Onboarding, About, Settings, ScreenShare) używają
  `MaterialTheme.colorScheme.*` — dynamic color podmieni je automatycznie, bez edycji komponentów.
- Hardkodowane: zielony „✓" w onboardingu (semantyczny) i czarny gradient na tapecie Maca
  (`MacMonitorCard`) — **zostają**.
- macOS — bez zmian (to redesign wyłącznie Androida).

## Testy / weryfikacja

- Po bumpie: `./gradlew :app:assembleDebug` musi przejść (naprawić breaking changes).
- `./gradlew :app:testDebugUnitTest` — istniejące testy nadal zielone.
- Weryfikacja ręczna e2e: jasny/ciemny motyw, dynamic color z różnych tapet (Android 12+),
  fallback na starszym API (lub emulatorze), płynność expressive animacji przejść połączenia.
- Brak testów jednostkowych dla samego motywu (wizualne) — weryfikacja ręczna.

## Poza zakresem (YAGNI)

- Redesign macOS. Custom branding/seed kolorów (idziemy dynamic+baseline). Nowe ekrany.
- Przeprojektowanie layoutów ekranów (zmieniamy motyw/kolory/animacje, nie układ treści).
- Toggle dynamic on/off w Ustawieniach (dynamic zawsze on z fallbackiem; można dołożyć później).

## Pliki dotknięte

- `android/Airbridge/app/build.gradle.kts`, `gradle/libs.versions.toml` — bump.
- `android/.../ui/Theme.kt` — MaterialExpressiveTheme + dynamic color + motion; usunięcie custom palet.
- `android/.../ui/MainScreen.kt` — expressive AnimatedContent dla stanu połączenia + `animateItem` listy.
- (Ewentualne punktowe naprawy breaking changes po bumpie w innych plikach `ui/`.)
