# macOS Liquid Glass — pełna adopcja w Airbridge

**Data:** 2026-04-11
**Autor design-u:** Marcin Baszewski (brainstorming z Claude)
**Deployment target:** macOS 26+
**Kierunek estetyczny:** Apple-native (restrained), idiomatyczny macOS 26

---

## 1. Zakres i cel

**Cel:** wyciągnąć macOS Airbridge na pełną adopcję Liquid Glass zgodnie z idiomami macOS 26, bez zmieniania funkcjonalności. Obecnie używamy `.glassEffect(in: .rect(cornerRadius: 16))` jako „dekoracji prostokątnej" na paru kartach — to jest ok. 20% możliwości toolkitu. Reszta (`GlassEffectContainer`, `glassEffectID`, `.interactive()`, `.scrollEdgeEffect`, concentric corners, `symbolEffect`, `contentTransition`) jest nieużywana.

### In-scope

1. **Shell** — `AirbridgeApp` + `MainWindow` — window chrome, sidebar, toolbar, scroll containers
2. **Primitives** — nowy folder `Views/Components/` z wielokrotnego użytku `ScreenContainer`, `GlassSection`, `SectionHeader`, `StatusIndicator`, `Animations`
3. **Content screens** — `HomeView`, `SendView`, `SettingsView`, `HistoryView`, `GalleryView`, `MessagesView`, `AboutView`, `PairingView`, `OnboardingView`
4. **Floating panels** — `TransferPopupView` (pełny rewrite z `Color.black` na Liquid Glass + `glassEffectID` morph między stanami), `DropZonePopup`/`DropZoneView` (analogiczny upgrade)

### Out-of-scope (w tym spec-u)

- Tryb ciemny/jasny tuning kolorystyki — Liquid Glass sam się dostosowuje
- Nowe animacje content-level — tylko systemowe spring-y i `symbolEffect`
- Refaktor ViewModels / serwisów — tylko widoki
- Onboarding copywriting i UX flow — tylko re-skin
- Apka Android
- Bugi z `project_status.md` (gallery date issue, SMS loading) — osobna sesja
- Testy jednostkowe widoków
- Localization audit

### Non-goals (świadomie odrzucone)

- Custom gradient backgrounds pod contentem — Apple-native znaczy że tło daje Liquid Glass + macOS desktop, nie my
- „Hero moments" z mocnym tintem, dramatic glows, particle effects — to jest kierunek showcase, z którego zrezygnowaliśmy na rzecz restrained

---

## 2. Shell architecture

### `AirbridgeApp.swift` (Scene level)

```swift
Window("Airbridge", id: "main") {
    // …
}
.defaultSize(width: 1100, height: 850)
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unified(showsTitle: true))
.containerBackground(.thickMaterial, for: .window)
```

**Dlaczego:** `containerBackground` na poziomie okna to fundament — dzięki temu całe okno jest „przeziernym pojemnikiem", a `.glassEffect` wewnątrz ma co blur-ować. Bez tego glass siedzi na solidnym tle i wygląda jak naklejka. `.thickMaterial` to bezpieczny wybór: czytelny, stonowany, zgodny z tym co Apple używa w Settings.app i Finder sidebar. `.hiddenTitleBar` + unified toolbar daje czyste wertykalne okno bez double-chrome.

### `MainWindow.swift` (TabView)

```swift
TabView(selection: $selectedTab) { ... }
    .tabViewStyle(.sidebarAdaptable)
    .toolbarBackground(.regularMaterial, for: .windowToolbar)
    .toolbar {
        ToolbarItem(placement: .principal) {
            // status sparowanego urządzenia — mały live indicator
        }
    }
```

Każdy `Tab { ... }` owinięty w shared wrapper `ScreenContainer`:

```swift
Tab("Home", systemImage: "house.fill", value: .home) {
    ScreenContainer {
        HomeView(...)
    }
}
```

---

## 3. Primitives — nowe wspólne komponenty

Nowy folder `macos/Airbridge/Sources/AirbridgeApp/Views/Components/` z plikami:

### `ScreenContainer.swift`

Wspólny wrapper dla contentu każdego ekranu.

```swift
struct ScreenContainer<Content: View>: View {
    var scroll: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            if scroll {
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollEdgeEffect(.soft, for: .top)
                .scrollEdgeEffect(.soft, for: .bottom)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

**Co to zmienia:**
- `GlassEffectContainer` — jeden blur layer dla całego contentu danego ekranu; wszystkie `.glassEffect(...)` w środku dzielą go. **To jest główna rzecz której brakuje w obecnej apce.**
- `.scrollEdgeEffect(.soft, for: .top/.bottom)` — content przy krawędziach scrolla rozmywa się (Apple standard w Settings.app).
- ScrollView + padding 24 wspólne → każdy ekran przestaje je sam deklarować.
- `scroll: false` wariant dla `GalleryView`, `MessagesView` które mają własną wewnętrzną hierarchię.

### `GlassSection.swift`

Primitive zastępujący wszystkie `VStack { ... }.padding(N).glassEffect(in: .rect(cornerRadius: M))` z HomeView/SettingsView/SendView.

```swift
struct GlassSection<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionHeader(title: title, systemImage: systemImage)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .containerRelative)
    }
}
```

**Kluczowe:** `in: .containerRelative` zamiast `in: .rect(cornerRadius: 16)`. `.containerRelative` dziedziczy zaokrąglenie od rodzica (window/GlassEffectContainer) minus padding → **concentric corners** Apple-style, bez magicznych liczb.

Dodatkowy wariant: `GlassRow` — ten sam primitive bez tytułu i z mniejszym paddingiem, do list (HistoryView, GalleryView grid, MessagesView conversations list).

### `SectionHeader.swift`

```swift
struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil

    var body: some View {
        Label(title, systemImage: systemImage ?? "")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
```

Jeden styl nagłówka sekcji w całej apce. Małe, uppercase, tracking — jak w Settings.app.

### `StatusIndicator.swift`

Primitive do wszystkich „kropek stanu". Warianty `.connected / .disconnected / .connecting / .error` z automatycznym doborem koloru i `symbolEffect`-u.

```swift
struct StatusIndicator: View {
    enum State { case connected, disconnected, connecting, error }
    let state: State
    // renderuje Circle() / Image z odpowiednim kolorem + symbolEffect
}
```

- `.connected` — zielona kropka (brak pulse-a, spokojna)
- `.connecting` — `antenna.radiowaves.left.and.right` z `.symbolEffect(.variableColor.cumulative.reversing)`
- `.disconnected` — szara kropka
- `.error` — `exclamationmark.circle.fill` czerwony, `.symbolEffect(.bounce)` jednorazowo

### `Animations.swift`

```swift
extension Animation {
    static let airbridgeQuick = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let airbridgeSmooth = Animation.spring(response: 0.55, dampingFraction: 0.75)
}
```

Single source of truth dla spring curves w całej apce.

---

## 4. Per-screen migration plan

### `HomeView.swift`

- **Usuwamy:** własny `ScrollView`, `VStack(spacing: 16).padding(24)`, wszystkie `.padding(16).glassEffect(in: .rect(cornerRadius: 16))` na 4 kartach, ręczne `Circle().fill(.green).shadow(...)` dla status-dota
- **Dodajemy:** content wchodzi do `ScreenContainer`. Każda karta (`connectionCard`, `transferCard`, `recentActivityCard`, `noPairedDevicesCard`) → `GlassSection(title:, systemImage:)`. Status-dot → `StatusIndicator`. State-transitions na `.airbridgeQuick`. Ikony stanu (`iphone.slash`, `exclamationmark.circle.fill`) dostają `symbolEffect(.bounce, value: vm.statusMessage)`. IP i prędkości transferu → `contentTransition(.numericText())`.

### `SendView.swift`

- **Usuwamy:** `VStack(spacing: 20).padding(24)`, ręczny dashed `RoundedRectangle` border, własny `ZStack` dla drop-zone, `.glassEffect` na transferującym progress-cardzie
- **Dodajemy:** content do `ScreenContainer`. Drop-zone przepisana na `GlassSection` z `.glassEffect(.regular.interactive(), in: .containerRelative)` — `interactive()` daje darmowy hover/press effect. `isTargeted` → `.regular.tint(.accentColor).interactive()` z `.airbridgeQuick`. Dashed border jako subtelny detail wewnętrzny, nie główna rama. `arrow.down.doc` z `symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)`. Progress card → `GlassSection`, `ProgressView` natywny `.linear` z `.tint(.accentColor)`.

### `SettingsView.swift`

- **Usuwamy:** 5× duplikat `VStack.padding(20).glassEffect(in: .rect(cornerRadius: 16))` dla 5 sekcji (Paired Devices / General / Quick Drop Shortcut / File Transfer / Connection)
- **Dodajemy:** każda z 5 sekcji → `GlassSection(title:, systemImage:)`. Accessibility + Connection status dots → `StatusIndicator`. Skrót (shortcut display) w monospaced pigułce → `.glassEffect(.regular, in: .capsule)` zamiast ręcznego `Color.white.opacity(0.1) + RoundedRectangle(cornerRadius: 6)`.

### `HistoryView.swift`

- **Zostaje:** tintowany glass na ikonkach (`.regular.tint(.blue)`, `.regular.tint(.green)`) — już jest dobrze.
- **Usuwamy:** własny `ScrollView`, `LazyVStack.padding(16)`, per-row `.padding(...).glassEffect(in: .rect(cornerRadius: 12))`
- **Dodajemy:** content → `ScreenContainer`. Wiersze dalej w `LazyVStack(spacing: 6)`, każdy wiersz owijamy w `GlassRow`. Empty-state z `Image(systemName: "clock").symbolEffect(.pulse)`. Kierunek sent/received → ikonka z `contentTransition(.symbolEffect(.replace))`.

### `GalleryView.swift`

- `ScreenContainer(scroll: false)` bo ma własny grid scroll.
- Grid thumbnails: każda miniatura dostaje `.glassEffect(.regular, in: .rect(cornerRadius: 8))` jako subtelne obramowanie. Hover → `.interactive()`.
- Toolbar z filtrami / odświeżaniem → `GlassSection` jako sticky header.
- **Performance note:** thumbnails NIE dostają własnych `GlassEffectContainer`-ów — to by zabiło GPU przy setkach obrazów. Tylko simple `.glassEffect` border, inherit z głównego containera ekranu.

### `MessagesView.swift`

- `ScreenContainer(scroll: false)` — ma `HSplitView` z listą konwersacji + detail.
- Lista konwersacji — każdy wiersz `GlassRow` z `.interactive()`.
- Detail view — bubble'e wiadomości z `.glassEffect(.regular.tint(...), in: .containerRelative)`: sent → `.tint(.accentColor)`, received → `.regular`. iMessage-like feel bez bycia kopią.
- Loading indicator na wiadomościach — `symbolEffect(.pulse)` zamiast `ProgressView`.

### `AboutView.swift`

- Content w `ScreenContainer`. Logo, wersja, credits w pojedynczym wyśrodkowanym `GlassSection` z mniejszym paddingiem.

### `PairingView.swift` (sheet)

- `.presentationBackground(.thinMaterial)` — sam sheet jest glass-em nad oknem.
- QR code w środku `GlassSection`.
- Status kroków pairing-u (waiting / connecting / verifying / done) → `symbolEffect(.variableColor, options: .repeating)` na ikonkach progresu.

### `OnboardingView.swift`

- `.presentationBackground(.thinMaterial)` albo `containerBackground` jeśli pełne okno.
- `GlassSection` na każdy krok.
- SF Symbols z `symbolEffect` na transitions między krokami.

### `DropZoneView.swift`

Szczegóły w Sekcji 6.

---

## 5. TransferPopupView rewrite

### Co jest dziś

`TransferPopupView.swift` zawiera:
- Ręcznie wymalowany `Color.black` background via `BottomRoundedShape` (custom `Path`)
- Biały tekst hardcoded (`.foregroundColor(.white.opacity(0.5))` wszędzie)
- 5 wariantów UI w jednym `ZStack` (incoming offer / rejected / waiting / complete / transferring)
- Ręczny `ProgressView` z linear gradient przez `GeometryReader` + `RoundedRectangle`
- Custom `MarqueeText` z `Timer`, `DispatchQueue.main.asyncAfter`, ręcznymi offsetami (~80 linii)
- Pozycjonowanie + slide-in animacja przez `NSWindow` + `Timer(timeInterval: 1.0/60.0)` + `CACurrentMediaTime`

**To wszystko idzie do wyrzucenia.** Liquid Glass + `glassEffectID` + natywne animacje okna robią 90% tego natywnie.

### Nowa architektura

**`TransferPopupState.swift`** — nowy enum, state machine:

```swift
enum TransferPopupState: Equatable {
    case incoming(IncomingOffer)
    case waiting(filename: String)
    case transferring(TransferInfo)
    case complete(TransferKind)
    case rejected(filename: String)
}
```

Mapowany z `FileTransferService` w jednym miejscu w `TransferPopupView`.

**`TransferPopupView.swift`** — przepisany:

```swift
struct TransferPopupView: View {
    let fileTransferService: FileTransferService
    @Namespace private var glassNS

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            Group {
                switch state {
                case .incoming(let offer):    incomingView(offer)
                case .waiting(let name):      waitingView(name)
                case .transferring(let info): transferringView(info)
                case .complete(let kind):     completeView(kind)
                case .rejected(let name):     rejectedView(name)
                }
            }
            .glassEffect(
                .regular.tint(tintFor(state)),
                in: .rect(cornerRadius: 28, style: .continuous)
            )
            .glassEffectID("popup", in: glassNS)
        }
        .frame(width: 560)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .shadow(radius: 30, y: 12)
    }

    private var state: TransferPopupState { /* derived from service */ }

    private func tintFor(_ s: TransferPopupState) -> Color {
        switch s {
        case .incoming, .waiting, .transferring: return .accentColor
        case .complete: return .green
        case .rejected: return .red
        }
    }
}
```

**Kluczowe decyzje:**

1. **`GlassEffectContainer` + `glassEffectID("popup", in: glassNS)`** — Liquid Glass sam robi spring morph glass-shape gdy zmienia się wewnętrzny `Group`. Zero manualnych animacji. To jest DOKŁADNIE use-case dla `glassEffectID`. **To jest ta natywna animacja której brakuje.**
2. **`.glassEffect(.regular.tint(color))`** zamiast `Color.black`. Tło popupa to prawdziwy Liquid Glass z subtelnym tintem zależnym od stanu.
3. **Tekst z `foregroundStyle(.primary/.secondary)`** zamiast hardcoded `.white.opacity(X)` → działa w light mode.
4. **Ikony z `symbolEffect`:**
   - `incoming` — `arrow.down.doc.fill` + `.symbolEffect(.bounce)`
   - `waiting` — `hourglass` + `.symbolEffect(.pulse, options: .repeating)`
   - `transferring sending` — `arrow.up.circle.fill` + `.symbolEffect(.variableColor, options: .repeating)`
   - `transferring receiving` — `arrow.down.circle.fill` + `.symbolEffect(.variableColor, options: .repeating)`
   - `complete` — `checkmark.circle.fill` + `.symbolEffect(.bounce)` + `.contentTransition(.symbolEffect(.replace))`
   - `rejected` — `xmark.circle.fill` + `.symbolEffect(.bounce)`
5. **Postęp → natywny `ProgressView(value:).progressViewStyle(.linear).tint(.accentColor)`**. Zero ręcznego gradient-rysowania.
6. **Speed/ETA/filename/procent** — `.contentTransition(.numericText())` — liczby morfują cyfra-po-cyfrze, nie migają.
7. **`MarqueeText` WYRZUCONE** — zamiast scrolla, filename leci przez `Text(name).lineLimit(1).truncationMode(.middle)`. Apple idiomatic = truncation, nie marquee. Usunięcie całej klasy `MarqueeText` (~80 linii + `Timer` machinery).

### Window-level — `TransferPopup` singleton

Zostaje (NSWindow, pozycjonowanie, show/hide), ale upraszczamy:

- **Slide-in / slide-out** — ręczny `Timer` + `CACurrentMediaTime` → `NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.35; ctx.timingFunction = CAMediaTimingFunction(name: .easeOut) ... }` + `window.setFrame(target, display: true, animate: true)`. Natywna animacja okna.
- **`BottomRoundedShape`** — USUNIĘTE. Liquid Glass `.rect(cornerRadius: 28, style: .continuous)` daje to samo + concentric-compatible.
- **Window config** (`isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`) — zostaje. Liquid Glass sam rysuje cień, a `.shadow(radius: 30, y: 12)` na SwiftUI daje dodatkowy miękki drop-shadow dla głębi.

### Co zyskujemy

- **~200 linii kodu mniej** (MarqueeText, BottomRoundedShape, ręczny gradient ProgressView, ręczne animacje slide)
- **Prawdziwy Liquid Glass popup** — wtapia się z desktopem, nie jest czarną naklejką
- **Natywny morph** między stanami — jak Dynamic Island na iOS
- **Light/dark mode** działa automatycznie
- **Reduce-motion / increase-contrast** respektowane automatycznie

---

## 6. DropZonePopup rewrite

Analogiczna struktura do TransferPopup — osobny `NSWindow`, osobny SwiftUI view, osobny show/hide. Dziś `DropZonePopup.swift` używa identycznego wzorca z ręcznym `Timer` + `CACurrentMediaTime`.

### Co jest dziś w `DropZoneView.swift`

Potwierdzone czytaniem kodu — **dokładnie ten sam grzech co TransferPopupView**:
- `BottomRoundedShape(radius:).fill(Color.black)` jako root background (ten sam custom `Path` co w TransferPopup)
- Dodatkowo **drugi custom `Path`** — `UShape` — rysujący dashed border w kształcie „U" (bez górnej krawędzi, bo panel jest przypięty pod notchem)
- Biały tekst hardcoded (`.foregroundColor(.white.opacity(0.65))`, `.white.opacity(0.25))`, itd.)
- Ręczny `spring` transition na `isTargeted` z własnym `scaleEffect(1.015)` (mikro-bounce)
- `@AppStorage("islandWidth/Height/CornerRadius")` współdzielone z `TransferPopup`

**Do usunięcia:** `BottomRoundedShape` (wspólne z TransferPopup — usunięcie globalne po Sekcji 5 i 6), **cały `UShape` struct**, wszystkie hardcoded `Color.white.opacity(...)`. `@AppStorage` island keys **zostają** (dalej używane przez oba popup-y do pozycjonowania, tylko w `DropZoneView` nie będą dłużej determinować shape-u, tylko frame size).

### `DropZoneView.swift`

```swift
struct DropZoneView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let onFileDrop: () -> Void

    @State private var isTargeted = false

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 18) {
                header    // tytuł + connection status
                dropArea  // duża strefa drop z interactive glass
                footer    // hint tekst + escape hint
            }
            .padding(24)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: 28, style: .continuous)
            )
        }
        .shadow(radius: 40, y: 16)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { ... }
    }

    private var dropArea: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 56, weight: .light))
                .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                .symbolEffect(.bounce, value: isTargeted)
            Text(L10n.dropFilesHere)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .glassEffect(
            isTargeted
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .animation(.airbridgeQuick, value: isTargeted)
    }
}
```

**Kluczowe decyzje:**

1. **Dwie warstwy glass-a w jednym containerze** — outer glass panel + inner interactive drop-area. Legit pattern (Apple tak robi w Control Center).
2. **`.interactive()` na drop-area** — hover/press feedback bez kodu po naszej stronie.
3. **Tint przy `isTargeted`** — glass mieni się accentColor-em gdy pliki są nad nim, z `.airbridgeQuick` spring animation.
4. **Ikona** pulsuje „przyciągająco" gdy pusto, przerywa i robi `.bounce` przy drop-ie.
5. **`shadow(radius: 40, y: 16)`** — miękki głęboki drop-shadow dla floating feel (`window.hasShadow = false`, Liquid Glass rysuje swój cień, tu chcemy wyraźniejszy bo panel jest duży).

### `DropZonePopup` window-level

Analogicznie do `TransferPopup`:
- Slide-in/out → `NSAnimationContext` + `window.setFrame(..., animate: true)`
- Auto-hide timer i escape monitor zostają (logika, nie wygląd)
- Window config (borderless, clear, screenSaver level) zostaje

### Nota implementacyjna

Sekcje 5 i 6 mają bardzo podobną strukturę window-level. Jeśli podczas implementacji naturalnie się zapisze wspólny helper `FloatingPanelWindow` (show/hide z natywną animacją, auto-hide timer, escape monitor, pozycjonowanie) — dobrze. Jeśli nie — zostawiamy dwa podobne pliki. **To nie jest goal speca**, tylko dopuszczalny refactor przy okazji.

---

## 7. Motion & animation conventions

### 1. Żadnych ręcznych Timerów do animacji

Dziś są **trzy** ręczne Timery (`TransferPopup.show`, `TransferPopup.hide`, `DropZonePopup.show/hide`) robiące 60fps pętle. Wszystkie znikają → natywna `NSAnimationContext` + `window.setFrame(..., animate: true)`.

### 2. Standardowe spring curves

Dwa preset-y w `Animations.swift`:
- `.airbridgeQuick` — `spring(response: 0.4, dampingFraction: 0.85)` — szybki, stonowany. Dla: state-change kart, toggle-i, appear/disappear.
- `.airbridgeSmooth` — `spring(response: 0.55, dampingFraction: 0.75)` — wolniejszy, lekko rozbujany. Dla: sheet transitions, popup morph, większe przejścia.

### 3. `symbolEffect` jako standard dla ikon statusu

| Stan | Ikona | Efekt |
|---|---|---|
| connecting | `antenna.radiowaves.left.and.right` | `.variableColor.cumulative.reversing` |
| transferring | `arrow.up/down.circle.fill` | `.variableColor, options: .repeating` |
| waiting | `hourglass` | `.pulse, options: .repeating` |
| complete | `checkmark.circle.fill` | `.bounce` (jednorazowe) |
| error | `exclamationmark.circle.fill` | `.bounce` (jednorazowe) |
| drop zone idle | `arrow.down.doc` | `.pulse, options: .repeating, isActive: !isTargeted` |
| notification appear | dowolna | `.bounce` z `value: trigger` |

### 4. `contentTransition` dla zmieniających się wartości

- Progres %, MB/s, ETA, IP, filename-y → `.contentTransition(.numericText())`
- Kierunek sent/received w HistoryView → `.contentTransition(.symbolEffect(.replace))`
- Status label text → `.contentTransition(.interpolate)`

### 5. `matchedGeometryEffect` i `glassEffectID`

- HomeView `connectionCard` state change (`disconnected → connecting → connected`) → `matchedGeometryEffect` na wewnętrznym layoucie, status-dot / device name / przycisk płynnie zmieniają pozycje zamiast re-mountować.
- TransferPopup state change → `glassEffectID` (mocniejsze narzędzie, morfuje sam glass-kształt).

### 6. Zakaz ręcznych „glow"-ów

Dzisiejsze `Circle().fill(.green).shadow(color: .green.opacity(0.6), radius: 6).shadow(color: .green.opacity(0.3), radius: 12)` w HomeView → usuwamy. W Apple-native nie robimy glow-ów ręcznie. `StatusIndicator(.connected)` używa natywnych środków (kropka + `symbolEffect`).

### 7. Reduce-motion awareness

Wszystko co opisane wyżej **automatycznie** respektuje `accessibilityReduceMotion`. Nie musimy nic robić. Dodatkowy bonus: wyrzucenie ręcznych `Timer`-ów to darmowy fix dostępności (stary kod nie respektował reduce-motion).

---

## 8. Success criteria & verification

### Code-level (checki automatyczne, grep-owalne)

Po zakończeniu prac w `macos/Airbridge/Sources/AirbridgeApp/` powinno być prawdą:

1. **Zero** `.glassEffect(in: .rect(cornerRadius:` — każde wystąpienie zastąpione `GlassSection` lub `.containerRelative` shape
2. **Zero** `Color.black` i hardcoded `Color.white.opacity(...)` jako background/foreground (tekst pozostaje na `.primary/.secondary/.tertiary`)
3. **Zero** `Timer.scheduledTimer` / `Timer(timeInterval: 1.0/60.0)` w `Views/` (były w TransferPopup, DropZonePopup, MarqueeText)
4. **Zero** `BottomRoundedShape`, **zero** `UShape`, zero `CACurrentMediaTime()` w kontekście animacji widoków, zero custom `Path` backgroundów w `Views/`
5. **Zero** `MarqueeText` (usunięte całkowicie)
6. **Co najmniej jeden** `GlassEffectContainer` w `ScreenContainer.swift`
7. **Co najmniej jeden** `glassEffectID` + `@Namespace` w `TransferPopupView.swift`
8. **Każdy** `ScrollView` w `Views/` jest albo wewnątrz `ScreenContainer`, albo ma własny `.scrollEdgeEffect(...)` — zero „gołych" ScrollView
9. **Każda** sekcja contentu idzie przez `GlassSection` (wszystkie wystąpienia `VStack { ... }.padding(...).glassEffect(...)` poza `Views/Components/` zniknęły)
10. **Wszystkie** widoki importują i używają primitive-ów z `Views/Components/`

### User-level (manualna weryfikacja w odpalonej apce)

Po builde + odpaleniu z `$HOME/Applications/Airbridge.app` (**nie z DMG**, per `feedback_no_auto_install.md`):

1. **Window chrome** — tytuł w unified toolbar, nie w osobnym title-barze; tło okna Liquid-Glass-przezierne (wallpaper widoczny jako subtelny blur)
2. **Scroll edges** — na każdym ekranie content rozmywa się przy górnej i dolnej krawędzi przewijania
3. **Hover** — najechanie myszką na drop-zone w SendView lub konwersację w Messages daje subtelny „wypchnięty" glass feedback
4. **Status transitions** — klik „Rozłącz" → status-dot płynnie morfuje z zielonego do szarego, device name crossfade-uje do „Rozłączono", bez migotania
5. **TransferPopup lifecycle** — inicjacja transferu z telefonu: popup zjeżdża z góry natywną animacją, przechodzi przez stany `waiting → transferring → complete` z widocznym glass morph-em; nigdy nie wygląda jak czarny pasek
6. **DropZonePopup** — Cmd+Shift+V otwiera panel przezierny (widać desktop pod spodem); ikona `arrow.down.doc` pulsuje; drop pliku → bounce + spring transition + panel znika
7. **Reduce motion** — System Settings → Accessibility → Display → Reduce Motion; animacje stają się crossfade-ami, nic się nie psuje
8. **Light mode** — przełączenie na light appearance; cała apka czytelna, TransferPopup ma jasne tło z ciemnym tekstem (dziś zawsze czarny)

### Jak weryfikujemy podczas pracy

- **Po każdym ekranie** — `swift build` + build script, lokalny run, manual test punktów 1-3 dla danego ekranu
- **Na końcu** — pełny przejazd po wszystkich user-level checklistach
- **Zero unit testów** na widoki — verification = build + manual test

---

## 9. Risks, dependencies, out-of-scope

### Ryzyka

1. **`.containerRelative` shape i `GlassEffectContainer` wymagają macOS 26.** `Package.swift` już ma `platforms: [.macOS("26.0")]`, więc bezpiecznie. Założenie: macOS 26 zostaje deployment target.

2. **`glassEffectID` + morph — świeże API.** Nie wszystkie kombinacje kształtów dają ładny morph. Jeśli przejście `incoming → waiting → transferring` ma glitch, fallback: `withAnimation(.airbridgeSmooth) { state = ... }` z prostym opacity transition bez glass-morph-a. Ryzyko estetyczne, nie funkcjonalne.

3. **`.interactive()` glass + `.onDrop`.** Może wchodzić w konflikt z `.onDrop(isTargeted:)` (hit-test region). Mitygacja: jeśli wystąpi, rozdzielamy — outer glass bez `.interactive()`, inner hit-test bez glass, styling via `.background(.glass...)`. Ryzyko lokalne (SendView, DropZoneView).

4. **`TransferPopup` na `window.level = .screenSaver`.** Liquid Glass ma blurować content pod spodem, ale na screenSaver level to nie jest standardowy use-case Apple. Jeśli blur jest pusty (system nie daje content under screenSaver windows), fallback: `window.level = .popUpMenu`. Trade-off: popup nie będzie nad full-screen apps. Do przetestowania.

5. **Performance — `GalleryView`.** `GlassEffectContainer` + setki thumbnail-i może być kosztowne GPU-wo. Mitygacja: thumbnails dostają tylko `.regular` glass jako border, bez własnego container-owania. Jeśli framerate spada, zdejmujemy glass z thumbnail-i całkiem.

### Zależności

- macOS 26 SDK — jest
- swift-tools-version 6.2 — jest
- Zero nowych zewnętrznych pakietów — wszystko natywne SwiftUI + AppKit
- Brak wpływu na Protocol / Networking / FileTransfer / Pairing / Security libraries — to czysto widokowa robota

### Out-of-scope (explicit)

- Android apka
- Logic warstwy (ViewModels, Services) poza dodawaniem `@Namespace` property tam gdzie potrzebne dla `glassEffectID`
- Protocol / Networking / Security libraries
- Nowe feature-y — zero nowej funkcjonalności
- Bugi z `project_status.md`
- Unit testy widoków
- Localization audit

---

## Kolejność implementacji (preview dla writing-plans)

Sugerowana kolejność realizacji, którą zabierze writing-plans skill do szczegółowego planu:

1. **Components foundation** — stworzyć `Views/Components/{Animations, SectionHeader, StatusIndicator, GlassSection, ScreenContainer}.swift` (no wire-up)
2. **Shell** — zaktualizować `AirbridgeApp.swift` i `MainWindow.swift` (containerBackground, windowStyle, ScreenContainer wrapping)
3. **HomeView migration** — pierwszy ekran pokazowy, sanity check całego primitive stacka
4. **Reszta content screens** — SettingsView, SendView, HistoryView, AboutView, GalleryView, MessagesView, PairingView, OnboardingView (kolejność: najprostsze najpierw)
5. **TransferPopupView rewrite** — pełna przeróbka (Sekcja 5)
6. **DropZoneView / DropZonePopup rewrite** — analogiczna (Sekcja 6)
7. **Motion sweep** — usunięcie pozostałych ręcznych Timerów, dodanie `symbolEffect` tam gdzie jeszcze brakuje, `contentTransition` na numerycznych wartościach
8. **Final verification** — grep-check na wszystkie code-level criteria z Sekcji 8, manual test user-level checklisty
