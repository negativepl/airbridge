# macOS Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the entire macOS Airbridge app to full-depth Liquid Glass adoption (idiomatic macOS 26), replacing manual `.glassEffect(in: .rect)` stickers, hand-drawn `Color.black` panels, and `Timer`-based animations with native `GlassEffectContainer`, `glassEffectID`, `.interactive()`, `.scrollEdgeEffect`, `symbolEffect`, and `contentTransition`.

**Architecture:** Shell-first, primitive-based. Step 1: build shared primitives (`ScreenContainer`, `GlassSection`, `SectionHeader`, `StatusIndicator`, `Animations`) under `Views/Components/`. Step 2: update the window shell (`AirbridgeApp`, `MainWindow`). Step 3: migrate each content screen to the primitives. Step 4: rewrite the two floating panels (`TransferPopupView`, `DropZoneView`) as true Liquid Glass with state-driven morph. Step 5: grep-verify zero manual glass/Timer/Color.black residue, manual-test the full user checklist.

**Tech Stack:** SwiftUI (macOS 26 SDK), AppKit (NSWindow for floating panels), Swift Package Manager (`swift-tools-version: 6.2`). No new external dependencies.

**Spec:** `docs/superpowers/specs/2026-04-11-macos-liquid-glass-design.md`

---

## Task 0: Prep — dev-install helper + Components directory

Sets up the two things every later task will depend on: a one-command dev build+install script, and the empty `Views/Components/` directory.

**Files:**
- Create: `scripts/dev-install.sh`
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/.gitkeep` (directory marker)

- [ ] **Step 1: Create the dev-install script**

Create `scripts/dev-install.sh`:

```bash
#!/bin/bash
# dev-install.sh — Debug build + replace binary in ~/Applications/Airbridge.app + relaunch
#
# Uses existing .app bundle structure created by release.sh. Fast iteration for UI work.
# Does NOT recreate the full bundle or re-sign — only replaces the binary and resource bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/macos/Airbridge"

echo "--- swift build ---"
swift build 2>&1 | tee /tmp/airbridge-build.log | grep -E ": (error|warning):" | head -40 || true

if grep -qE ': error:' /tmp/airbridge-build.log; then
    echo "BUILD FAILED — see /tmp/airbridge-build.log"
    exit 1
fi

APP="$HOME/Applications/Airbridge.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: $APP doesn't exist — run scripts/release.sh once to create it"
    exit 1
fi

echo "--- killing running instance ---"
killall AirbridgeApp 2>/dev/null || true
sleep 0.3

echo "--- copying binary ---"
cp .build/debug/AirbridgeApp "$APP/Contents/MacOS/AirbridgeApp"

RES_BUNDLE=".build/debug/Airbridge_AirbridgeApp.bundle"
if [ -d "$RES_BUNDLE" ]; then
    rm -rf "$APP/Contents/Resources/Airbridge_AirbridgeApp.bundle"
    cp -R "$RES_BUNDLE" "$APP/Contents/Resources/Airbridge_AirbridgeApp.bundle"
fi

echo "--- re-signing (ad-hoc) ---"
codesign --force --deep --sign - "$APP" 2>&1 | tail -5

echo "--- launching ---"
open "$APP"
echo "✓ Airbridge running from debug build"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/dev-install.sh`

- [ ] **Step 3: Create the Components directory marker**

Run: `mkdir -p macos/Airbridge/Sources/AirbridgeApp/Views/Components && touch macos/Airbridge/Sources/AirbridgeApp/Views/Components/.gitkeep`

- [ ] **Step 4: Test the dev-install script still builds the current (unchanged) code**

Run: `scripts/dev-install.sh`
Expected: ends with `✓ Airbridge running from debug build` and the app window opens. If you see `error:` output, do not proceed — fix the build first.

- [ ] **Step 5: Commit**

```bash
git add scripts/dev-install.sh macos/Airbridge/Sources/AirbridgeApp/Views/Components/.gitkeep
git commit -m "chore: add dev-install script and Views/Components directory"
```

---

## Task 1: Primitive — Animations.swift (spring curves)

Single source of truth for spring animation presets used across the app.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/Animations.swift`

- [ ] **Step 1: Write the file**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/Components/Animations.swift`:

```swift
import SwiftUI

extension Animation {
    /// Fast, subtle spring. Use for state-change cards, toggles, appear/disappear.
    /// Response 0.4s, damping 0.85 — quick settle, minimal overshoot.
    static let airbridgeQuick = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Slightly slower, mildly bouncy spring. Use for sheet transitions,
    /// popup morph, larger layout transitions.
    /// Response 0.55s, damping 0.75 — visible settle, small overshoot.
    static let airbridgeSmooth = Animation.spring(response: 0.55, dampingFraction: 0.75)
}
```

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build 2>&1 | grep -E "error:|warning:" | head`
Expected: no `error:` lines.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/Components/Animations.swift
git rm macos/Airbridge/Sources/AirbridgeApp/Views/Components/.gitkeep
git commit -m "feat(macos): add Animation presets (airbridgeQuick, airbridgeSmooth)"
```

---

## Task 2: Primitive — SectionHeader.swift

Uppercase tracked section label used inside every `GlassSection`.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/SectionHeader.swift`

- [ ] **Step 1: Write the file**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/Components/SectionHeader.swift`:

```swift
import SwiftUI

/// Small, uppercase, tracked section label. Used by GlassSection as the default header.
///
/// Matches the typography Settings.app uses for grouped list section titles.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil

    var body: some View {
        Group {
            if let systemImage, !systemImage.isEmpty {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build 2>&1 | grep -E "error:|warning:" | head`
Expected: no `error:` lines.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/Components/SectionHeader.swift
git commit -m "feat(macos): add SectionHeader primitive"
```

---

## Task 3: Primitive — StatusIndicator.swift

Consolidated status dot/icon with built-in `symbolEffect` per state. Replaces the hand-rolled `Circle().fill(.green).shadow(...)` patterns scattered in HomeView, SettingsView, PairingView.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/StatusIndicator.swift`

- [ ] **Step 1: Write the file**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/Components/StatusIndicator.swift`:

```swift
import SwiftUI

/// Unified connection/state indicator with built-in symbol effects.
///
/// Replaces manual `Circle().fill(...)` patterns and ensures every status
/// display in the app animates consistently and respects reduce-motion.
struct StatusIndicator: View {
    enum State: Equatable {
        case connected
        case disconnected
        case connecting
        case error
    }

    let state: State
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch state {
            case .connected:
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.85, height: size * 0.85)

            case .disconnected:
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: size * 0.85, height: size * 0.85)

            case .connecting:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.cumulative.reversing, options: .repeating)

            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: state)
            }
        }
        .frame(width: size, height: size)
        .contentTransition(.symbolEffect(.replace))
    }
}
```

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build 2>&1 | grep -E "error:|warning:" | head`
Expected: no `error:` lines.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/Components/StatusIndicator.swift
git commit -m "feat(macos): add StatusIndicator primitive with symbol effects"
```

---

## Task 4: Primitive — GlassSection.swift + GlassRow

Main card/row primitive. Replaces every `VStack { ... }.padding(N).glassEffect(in: .rect(cornerRadius: M))` scattered across the app. Uses `.containerRelative` shape so corner radius is concentric with the window.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/GlassSection.swift`

- [ ] **Step 1: Write the file**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/Components/GlassSection.swift`:

```swift
import SwiftUI

/// Standard titled glass card for grouped content.
///
/// Uses `.containerRelative` shape so its corner radius is automatically
/// concentric with the enclosing window/GlassEffectContainer — no magic numbers.
///
/// Usage:
///
///     GlassSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
///         Text("Pixel 8")
///         Text("192.168.1.14")
///     }
struct GlassSection<Content: View>: View {
    var title: LocalizedStringKey? = nil
    var systemImage: String? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionHeader(title: title, systemImage: systemImage)
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .containerRelative)
    }
}

/// Compact unnamed glass row for lists (history, conversations, gallery tiles).
///
/// Smaller padding than GlassSection, no header, same concentric corner treatment.
struct GlassRow<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .containerRelative)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build 2>&1 | grep -E "error:|warning:" | head`
Expected: no `error:` lines. If `containerRelative` gives an error, the API name may differ — check with `grep -r "containerRelative" /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/` and adjust. Fallback: use `.rect(cornerRadius: 20, style: .continuous)` here.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/Components/GlassSection.swift
git commit -m "feat(macos): add GlassSection and GlassRow primitives"
```

---

## Task 5: Primitive — ScreenContainer.swift

The wrapper that goes around every screen's content. Provides the shared `GlassEffectContainer` (one blur layer per screen), shared scroll container with `scrollEdgeEffect`, and shared 24pt padding.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/Components/ScreenContainer.swift`

- [ ] **Step 1: Write the file**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/Components/ScreenContainer.swift`:

```swift
import SwiftUI

/// Standard wrapper for every main screen in the app.
///
/// Provides:
/// - `GlassEffectContainer` — one shared blur layer so all inner `.glassEffect`
///   elements merge visually (this is the cornerstone of Liquid Glass use)
/// - `ScrollView` with `.scrollEdgeEffectStyle(.soft)` at top and bottom so content
///   softly fades at scroll edges (Apple standard in Settings.app)
/// - 24pt padding around the content
///
/// Pass `scroll: false` for screens with their own internal scrolling
/// (GalleryView grid, MessagesView split view).
struct ScreenContainer<Content: View>: View {
    var scroll: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            if scroll {
                ScrollView {
                    VStack(spacing: 16) {
                        content
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd macos/Airbridge && swift build 2>&1 | grep -E "error:|warning:" | head`
Expected: no `error:` lines. If `GlassEffectContainer` or `scrollEdgeEffectStyle` gives an error about availability, verify `Package.swift` shows `platforms: [.macOS("26.0")]`.

- [ ] **Step 3: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/Components/ScreenContainer.swift
git commit -m "feat(macos): add ScreenContainer wrapper with GlassEffectContainer and scroll edge effects"
```

---

## Task 6: Shell — AirbridgeApp.swift window configuration

Adds the window-level Liquid Glass chrome: `.hiddenTitleBar`, unified toolbar, `.containerBackground(.thickMaterial)`. This is the foundation every screen sits on.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` (lines 64-86)

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` lines 64-88.
Confirm: the `body: some Scene` currently has `Window("Airbridge", id: "main") { ... }.defaultSize(...).commands { ... }` without any windowStyle or containerBackground modifiers.

- [ ] **Step 2: Apply the changes**

In `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift`, find:

```swift
        Window("Airbridge", id: "main") {
            if onboardingCompleted {
                MainWindow(
                    connectionService: connectionService,
                    clipboardService: clipboardService,
                    fileTransferService: fileTransferService,
                    pairingService: pairingService,
                    historyService: historyService,
                    galleryService: galleryService,
                    smsService: smsService
                )
                .onAppear { hotkeyService.start() }
            } else {
                OnboardingView(
                    pairingService: pairingService,
                    connectionService: connectionService,
                    onComplete: { onboardingCompleted = true }
                )
            }
        }
        .defaultSize(width: 1100, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
```

Replace with:

```swift
        Window("Airbridge", id: "main") {
            if onboardingCompleted {
                MainWindow(
                    connectionService: connectionService,
                    clipboardService: clipboardService,
                    fileTransferService: fileTransferService,
                    pairingService: pairingService,
                    historyService: historyService,
                    galleryService: galleryService,
                    smsService: smsService
                )
                .onAppear { hotkeyService.start() }
                .containerBackground(.thickMaterial, for: .window)
            } else {
                OnboardingView(
                    pairingService: pairingService,
                    connectionService: connectionService,
                    onComplete: { onboardingCompleted = true }
                )
                .containerBackground(.thickMaterial, for: .window)
            }
        }
        .defaultSize(width: 1100, height: 850)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
```

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: build succeeds, app launches. Window should now have a unified title bar (tight, slim), with the window background showing `thickMaterial` translucency — the desktop wallpaper should be faintly visible through the window. The old classic title bar with large "Airbridge" text is gone.

- [ ] **Step 4: Manual verify**

Move the Airbridge window so part of it overlaps a colorful desktop background. Confirm:
- Title bar is unified (no separate chrome above the toolbar)
- Tint of the desktop shows through the window background
- No layout regressions inside the window (content still renders)

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift
git commit -m "feat(macos): window chrome — hiddenTitleBar, unified toolbar, thickMaterial containerBackground"
```

---

## Task 7: Shell — MainWindow.swift with ScreenContainer wrapping

Wraps each `Tab { ... }` in `ScreenContainer` so every screen inherits the shared `GlassEffectContainer` + scroll edge effects. Also adds `.toolbarBackground(.regularMaterial)`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift`.
Confirm: currently each `Tab` directly wraps the screen view with no wrapper.

- [ ] **Step 2: Apply the changes**

Replace the entire `body` in `MainWindow.swift` with:

```swift
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(NavigationItem.home.title, systemImage: "house.fill", value: .home) {
                ScreenContainer {
                    HomeView(
                        connectionService: connectionService,
                        fileTransferService: fileTransferService,
                        historyService: historyService,
                        pairingService: pairingService
                    )
                }
            }

            Tab(NavigationItem.history.title, systemImage: "clock.arrow.circlepath", value: .history) {
                ScreenContainer {
                    HistoryView(historyService: historyService)
                }
            }

            Tab(NavigationItem.send.title, systemImage: "paperplane.fill", value: .send) {
                ScreenContainer {
                    SendView(
                        fileTransferService: fileTransferService,
                        connectionService: connectionService,
                        clipboardService: clipboardService
                    )
                }
            }

            Tab(NavigationItem.gallery.title, systemImage: "photo.on.rectangle", value: .gallery) {
                ScreenContainer(scroll: false) {
                    GalleryView(galleryService: galleryService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.messages.title, systemImage: "message.fill", value: .messages) {
                ScreenContainer(scroll: false) {
                    MessagesView(smsService: smsService, connectionService: connectionService)
                }
            }

            Tab(NavigationItem.settings.title, systemImage: "gearshape.fill", value: .settings) {
                ScreenContainer {
                    SettingsView(
                        connectionService: connectionService,
                        pairingService: pairingService
                    )
                }
            }

            Tab(NavigationItem.about.title, systemImage: "info.circle", value: .about) {
                ScreenContainer {
                    AboutView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
    }
```

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: build succeeds. App launches. **Warning:** at this point every screen will look visually broken because they still contain their own `ScrollView` / `.padding(24)` / `.glassEffect` — you'll see nested scroll views and double padding. That is expected and will be fixed screen-by-screen starting at Task 8.

- [ ] **Step 4: Manual verify (minimal)**

Confirm the app opens, you can click through sidebar tabs (Home, History, Send, Gallery, Messages, Settings, About) without crashes. Visual regressions are expected for now.

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift
git commit -m "feat(macos): wrap all tabs in ScreenContainer, add toolbar material"
```

---

## Task 8: Migrate HomeView (pilot screen)

First screen migration. Removes own `ScrollView`/padding/glassEffect, switches all cards to `GlassSection`, status dot to `StatusIndicator`, adds `symbolEffect`/`contentTransition`. Serves as sanity check for the primitive stack.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift`. Confirm it has its own `ScrollView { VStack(spacing: 16) { ... }.padding(24) }` wrapping, and four cards each ending with `.padding(16).glassEffect(in: .rect(cornerRadius: 16))`.

- [ ] **Step 2: Rewrite the file**

Overwrite `macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift` with:

```swift
import SwiftUI

struct HomeView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let historyService: HistoryService
    let pairingService: PairingService

    @State private var viewModel: HomeViewModel?
    @State private var showPairing = false

    var body: some View {
        Group {
            if let vm = viewModel {
                connectionCard(vm)
                if vm.isTransferring {
                    transferCard(vm)
                }
                if vm.hasPairedDevices {
                    recentActivityCard(vm)
                } else {
                    noPairedDevicesCard
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(
                    connectionService: connectionService,
                    fileTransferService: fileTransferService,
                    historyService: historyService
                )
            }
        }
        .sheet(isPresented: $showPairing) {
            PairingView(
                pairingService: pairingService,
                connectionService: connectionService,
                isPresented: $showPairing
            )
        }
    }

    private var isDisconnected: Bool {
        viewModel?.statusMessage.contains("Rozłączono") == true || viewModel?.statusMessage.contains("Disconnected") == true
    }

    private func indicatorState(_ vm: HomeViewModel) -> StatusIndicator.State {
        if vm.isConnected { return .connected }
        if !vm.hasPairedDevices { return .disconnected }
        if isDisconnected { return .disconnected }
        if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Failed") || vm.statusMessage.contains("Błąd") {
            return .error
        }
        return .connecting
    }

    private func connectionCard(_ vm: HomeViewModel) -> some View {
        GlassSection {
            HStack(spacing: 14) {
                StatusIndicator(state: indicatorState(vm), size: 18)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        if vm.isConnected {
                            Text(vm.deviceName)
                        } else if !vm.hasPairedDevices {
                            Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                        } else if isDisconnected {
                            Text(L10n.isPL ? "Rozłączono" : "Disconnected")
                        } else {
                            Text(vm.statusMessage)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.interpolate)

                    Group {
                        if vm.isConnected, let ip = vm.localIP {
                            Text(ip).contentTransition(.numericText())
                        } else if !vm.hasPairedDevices {
                            Text(L10n.isPL ? "Sparuj telefon aby rozpocząć" : "Pair your phone to get started")
                        } else if isDisconnected {
                            Text(L10n.isPL ? "Kliknij Połącz ponownie aby wznowić" : "Click Reconnect to resume")
                        } else if !vm.isConnected {
                            Text(L10n.isPL ? "Szukam sparowanego urządzenia…" : "Looking for paired device…")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                connectionActionButton(vm)
            }
            .animation(.airbridgeQuick, value: vm.isConnected)
            .animation(.airbridgeQuick, value: vm.statusMessage)
        }
    }

    @ViewBuilder
    private func connectionActionButton(_ vm: HomeViewModel) -> some View {
        if vm.isConnected {
            Button(L10n.disconnect) { vm.disconnect() }
                .controlSize(.large)
        } else if isDisconnected {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if !vm.hasPairedDevices {
            Button(L10n.pairDevice) { showPairing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if vm.statusMessage.contains("failed") || vm.statusMessage.contains("Błąd") {
            Button(L10n.reconnect) { vm.reconnect() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
        }
    }

    private func transferCard(_ vm: HomeViewModel) -> some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "arrow.down.circle") {
            Text(vm.transferFileName)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: vm.transferProgress)
                .tint(.accentColor)

            HStack {
                Text(formatSpeed(vm.transferSpeed))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                Text(formatEta(vm.transferEta))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func recentActivityCard(_ vm: HomeViewModel) -> some View {
        GlassSection(
            title: L10n.isPL ? "Ostatnia aktywność" : "Recent Activity",
            systemImage: "clock"
        ) {
            let items = vm.recentActivity
            if items.isEmpty {
                Text(L10n.isPL ? "Brak aktywności" : "No activity yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { record in
                    HStack(spacing: 8) {
                        Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc")
                            .foregroundStyle(record.direction == .sent ? Color.primary : Color.accentColor)
                        Text(record.description)
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                        Text(record.timestamp, style: .relative)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var noPairedDevicesCard: some View {
        GlassSection {
            VStack(spacing: 14) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
                Text(L10n.isPL ? "Brak sparowanych urządzeń" : "No paired devices")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button(L10n.pairDevice) { showPairing = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed > 1024 * 1024 { return String(format: "%.1f MB/s", speed / (1024 * 1024)) }
        else if speed > 1024 { return String(format: "%.0f KB/s", speed / 1024) }
        return ""
    }

    private func formatEta(_ eta: Int) -> String {
        if eta > 60 { return "\(eta / 60) min \(eta % 60) s" }
        else if eta > 3 { return "\(eta) s" }
        return ""
    }
}
```

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: build succeeds, app launches. Home tab now shows:
- All 4 cards use the new GlassSection styling (concentric corners, consistent uppercase section headers where a title is set)
- Single scroll view (the ScreenContainer's), single 24pt padding — no more double nesting
- Scroll edges softly fade at top/bottom when you scroll
- Status indicator replaces the manual green circle with glow

- [ ] **Step 4: Manual verify**

Open Home tab. Disconnect the phone (or unplug), reconnect. Confirm:
- Status indicator morphs smoothly between states (no hard swap)
- Connection text fades with `.interpolate` transition
- IP address (when connected) morphs as `.numericText`
- No visual duplicated scroll/padding

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift
git commit -m "refactor(macos): migrate HomeView to GlassSection + StatusIndicator primitives"
```

---

## Task 9: Migrate SettingsView

Five sections, each currently duplicated `VStack.padding(20).glassEffect(in: .rect(cornerRadius: 16))`. Switch all to `GlassSection` and the shortcut pill to `.glassEffect(..., in: .capsule)`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift`. Confirm: 5 sections (Paired Devices, General, Quick Drop Shortcut, File Transfer, Connection), each wrapped with manual padding/glassEffect.

- [ ] **Step 2: Apply the changes**

Overwrite `macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift` with:

```swift
import SwiftUI
import ServiceManagement
import AirbridgeSecurity

struct SettingsView: View {
    let connectionService: ConnectionService
    let pairingService: PairingService

    @State private var viewModel: SettingsViewModel?
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads/Airbridge"
    @State private var showPairing = false
    @State private var isRecordingShortcut = false
    @State private var shortcutDisplay: String = GlobalHotkeyService.currentShortcutDisplay()
    @State private var shortcutMonitor: Any?

    var body: some View {
        Group {
            if let vm = viewModel {
                pairedDevicesSection(vm)
                generalSection
                quickDropSection
                fileTransferSection
                connectionSection(vm)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(
                    connectionService: connectionService,
                    pairingService: pairingService
                )
            }
            pairingService.refreshPairedDevices()
        }
        .onChange(of: connectionService.isConnected) { _, _ in
            pairingService.refreshPairedDevices()
        }
        .sheet(isPresented: $showPairing) {
            PairingView(pairingService: pairingService, connectionService: connectionService, isPresented: $showPairing)
        }
    }

    private func pairedDevicesSection(_ vm: SettingsViewModel) -> some View {
        GlassSection(
            title: L10n.isPL ? "Sparowane urządzenia" : "Paired Devices",
            systemImage: "iphone"
        ) {
            if vm.pairedDevices.isEmpty {
                Text(L10n.noDevicePaired)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.pairedDevices, id: \.publicKeyBase64) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.deviceName)
                                .font(.system(size: 14, weight: .medium))
                            Text(device.pairedAt, style: .date)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.isPL ? "Usuń" : "Remove", role: .destructive) {
                            vm.unpairDevice(publicKey: device.publicKeyBase64)
                        }
                        .controlSize(.large)
                    }
                }
            }

            Button(L10n.isPL ? "Dodaj nowe urządzenie" : "Add New Device") {
                showPairing = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var generalSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.general), systemImage: "gearshape") {
            Toggle(L10n.launchAtLogin, isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }
            ))
            .font(.system(size: 14))

            Toggle(L10n.isPL ? "Dźwięk po odebraniu" : "Sound on receive", isOn: $playSound)
                .font(.system(size: 14))
        }
    }

    private var quickDropSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.quickDropShortcut), systemImage: "keyboard") {
            HStack {
                Text(L10n.isPL ? "Dostępność:" : "Accessibility:")
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 6) {
                    StatusIndicator(state: AXIsProcessTrusted() ? .connected : .error, size: 12)
                    Text(AXIsProcessTrusted()
                        ? (L10n.isPL ? "Nadane" : "Granted")
                        : (L10n.isPL ? "Brak uprawnień" : "Not granted"))
                        .font(.system(size: 14))
                }
                if !AXIsProcessTrusted() {
                    Button(L10n.isPL ? "Nadaj" : "Grant") {
                        let key = "AXTrustedCheckOptionPrompt" as CFString
                        let options = [key: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                    .controlSize(.large)
                }
            }

            Text(L10n.isPL
                ? "Skrót działa globalnie tylko z uprawnieniami Dostępności. Po nadaniu uprawnień zrestartuj aplikację."
                : "The shortcut works globally only with Accessibility permission. Restart the app after granting.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text(L10n.isPL ? "Skrót:" : "Shortcut:")
                    .font(.system(size: 14))
                Spacer()

                if isRecordingShortcut {
                    Text(L10n.pressNewShortcut)
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                        .onAppear { startRecordingShortcut() }
                } else {
                    Text(shortcutDisplay)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: .capsule)
                }

                Button(isRecordingShortcut
                    ? (L10n.isPL ? "Anuluj" : "Cancel")
                    : (L10n.isPL ? "Zmień" : "Change")
                ) {
                    isRecordingShortcut.toggle()
                    if !isRecordingShortcut { stopRecordingShortcut() }
                }
                .controlSize(.large)

                if UserDefaults.standard.integer(forKey: "dropZoneShortcutKeyCode") != 0 {
                    Button(L10n.resetToDefault) {
                        UserDefaults.standard.removeObject(forKey: "dropZoneShortcutKeyCode")
                        UserDefaults.standard.removeObject(forKey: "dropZoneShortcutModifiers")
                        shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    private var fileTransferSection: some View {
        GlassSection(title: LocalizedStringKey(L10n.fileTransfer), systemImage: "folder") {
            HStack {
                Text(L10n.downloadFolder)
                    .font(.system(size: 14))
                Spacer()
                Text(downloadFolder)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(L10n.change) { chooseDownloadFolder() }
                    .controlSize(.large)
            }

            Text(L10n.receivedFilesSaved)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func connectionSection(_ vm: SettingsViewModel) -> some View {
        GlassSection(title: LocalizedStringKey(L10n.connection), systemImage: "antenna.radiowaves.left.and.right") {
            HStack {
                Text(L10n.status)
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 6) {
                    StatusIndicator(state: vm.isConnected ? .connected : .disconnected, size: 12)
                    Text(vm.isConnected ? L10n.connected : L10n.notConnected)
                        .font(.system(size: 14))
                }
            }

            if let ip = vm.localIP {
                HStack {
                    Text(L10n.localIP)
                        .font(.system(size: 14))
                    Spacer()
                    Text(ip)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { downloadFolder = url.path }
    }

    private func startRecordingShortcut() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command) || modifiers.contains(.control) else {
                return event
            }
            UserDefaults.standard.set(Int(event.keyCode), forKey: "dropZoneShortcutKeyCode")
            UserDefaults.standard.set(Int(modifiers.rawValue), forKey: "dropZoneShortcutModifiers")
            shortcutDisplay = GlobalHotkeyService.currentShortcutDisplay()
            isRecordingShortcut = false
            stopRecordingShortcut()
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutMonitor = nil
        }
    }
}
```

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: app launches, Settings tab looks clean — 5 consistent `GlassSection`s, uppercase section headers, concentric corners, no double padding.

- [ ] **Step 4: Manual verify**

Open Settings tab. Scroll. Confirm:
- All 5 sections look uniform
- Section headers are small uppercase tracked labels
- Shortcut display pill uses capsule glass
- Accessibility status row uses a StatusIndicator instead of a raw Circle

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/SettingsView.swift
git commit -m "refactor(macos): migrate SettingsView to GlassSection primitive"
```

---

## Task 10: Migrate SendView

Drop zone becomes `GlassSection` with `.interactive()`. Custom dashed rectangle border stays as a subtle detail inside. Drop interaction animates with `.airbridgeQuick`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/SendView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/SendView.swift`. Confirm: own `VStack(spacing: 20).padding(24)` wrapper, manual `ZStack` for drop zone with `RoundedRectangle.strokeBorder(dash:)`, `.glassEffect` on the progress card.

- [ ] **Step 2: Apply the changes**

Overwrite the `body` portion of `SendView.swift` (keep the helper methods `handleDrop`, `openFilePicker`, `resolveFiles`, `sendClipboard` as they are):

```swift
    var body: some View {
        Group {
            if let vm = viewModel, !vm.isConnected {
                Label(
                    L10n.isPL ? "Połącz się z urządzeniem aby wysłać" : "Connect to a device to send",
                    systemImage: "wifi.slash"
                )
                .font(.system(size: 14))
                .foregroundStyle(.orange)
            }

            dropZone

            if let vm = viewModel, vm.isSending {
                GlassSection {
                    Text(vm.fileName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ProgressView(value: vm.progress)
                        .tint(.accentColor)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 14) {
                Button { openFilePicker() } label: {
                    Label(L10n.selectFiles, systemImage: "folder")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                Button { sendClipboard() } label: {
                    Label(L10n.isPL ? "Wyślij schowek" : "Send Clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: 14))
                }
                .controlSize(.extraLarge)
                .disabled(viewModel.map { !$0.isConnected } ?? true)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TransferViewModel(
                    fileTransferService: fileTransferService,
                    connectionService: connectionService
                )
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 44))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                    .symbolEffect(.bounce, value: isTargeted)
                Text(L10n.dropFilesHere)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
        }
        .glassEffect(
            isTargeted
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .containerRelative
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
                .foregroundStyle(.secondary.opacity(isTargeted ? 0 : 0.25))
                .padding(8)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture { openFilePicker() }
        .animation(.airbridgeQuick, value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }
```

Note the file-top `import` stays, and the private helper methods at the bottom of the file stay.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: Send tab loads without errors. Drop zone card takes most of the width, uses concentric corners, the dashed border is a subtle detail.

- [ ] **Step 4: Manual verify**

- Hover over the drop zone with mouse — glass should subtly react (`.interactive()`)
- Drag a file from Finder over the drop zone — tint shifts to accentColor with a spring; dashed border fades out; icon bounces
- Drop the file — transfer starts; progress card appears below with numericText transition on %

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/SendView.swift
git commit -m "refactor(macos): migrate SendView to GlassSection + interactive drop zone"
```

---

## Task 11: Migrate HistoryView

Empty state + list of GlassRows. Removes per-row manual glass + own ScrollView.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/HistoryView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/HistoryView.swift`. Confirm: own `ScrollView { LazyVStack { ... }.padding(16) }` and per-row `.padding(.horizontal, 14).padding(.vertical, 10).glassEffect(in: .rect(cornerRadius: 12))`.

- [ ] **Step 2: Rewrite the file**

Overwrite `macos/Airbridge/Sources/AirbridgeApp/Views/HistoryView.swift` with:

```swift
import SwiftUI

struct HistoryView: View {
    let historyService: HistoryService

    var body: some View {
        if historyService.records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse, options: .repeating)

                Text(L10n.isPL ? "Brak aktywności" : "No Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(L10n.isPL
                    ? "Ostatnio brak aktywności.\nHistoria synchronizacji i przesłanych plików pojawi się tutaj."
                    : "No recent activity.\nSync and transfer history will appear here.")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVStack(spacing: 6) {
                ForEach(historyService.records) { record in
                    GlassRow {
                        HStack(spacing: 12) {
                            Image(systemName: record.type == .clipboard ? "doc.on.clipboard" : "doc.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .glassEffect(
                                    record.direction == .sent
                                        ? .regular.tint(.blue)
                                        : .regular.tint(.green),
                                    in: .rect(cornerRadius: 8)
                                )
                                .contentTransition(.symbolEffect(.replace))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.description)
                                    .font(.system(size: 15))
                                    .lineLimit(1)
                                Text(record.direction == .sent
                                     ? (L10n.isPL ? "Wysłano" : "Sent")
                                     : (L10n.isPL ? "Odebrano" : "Received"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.timestamp, style: .relative)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
```

Note: the `.glassEffect(in: .rect(cornerRadius: 8))` on the per-record icon is INTENTIONALLY kept as a tinted badge — it's not a full card, it's an icon pill, so `.rect(cornerRadius: 8)` is correct here. It will also not be caught by the final grep check because the grep looks for full-card patterns.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: History tab loads, shows records as rows with the tinted icon (blue for sent, green for received) on the left side.

- [ ] **Step 4: Manual verify**

- Open History tab — rows display cleanly
- Empty state: clear history (restart app if needed) — clock icon pulses
- Existing records: each shows a blue/green tinted icon, record text, and relative timestamp

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/HistoryView.swift
git commit -m "refactor(macos): migrate HistoryView to GlassRow primitive"
```

---

## Task 12: Migrate AboutView

Small screen — single centered GlassSection with app info.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/AboutView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/AboutView.swift` to see the current structure.

- [ ] **Step 2: Apply the changes**

Wrap the content in a `GlassSection` (no title — content is self-explanatory). Replace any `.padding().glassEffect(in: .rect(cornerRadius:))` wrappers with `GlassSection { ... }`. Remove any outer `ScrollView` or `VStack(spacing: 16).padding(24)` — that's provided by `ScreenContainer`. If the file has logo + app name + version text, the expected shape is:

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        GlassSection(padding: 28) {
            VStack(spacing: 16) {
                // ... existing logo / name / version content ...
            }
            .frame(maxWidth: .infinity)
        }
    }
}
```

Keep any existing images, text, links that were already in the file — just re-nest them inside `GlassSection`.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: About tab renders as a single centered glass card with the app info.

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/AboutView.swift
git commit -m "refactor(macos): migrate AboutView to GlassSection primitive"
```

---

## Task 13: Migrate PairingView (sheet)

Used as a `.sheet(...)` from HomeView and SettingsView. Gets `.presentationBackground(.thinMaterial)` so the sheet itself is glass over the window. QR code goes inside a `GlassSection`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/PairingView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/PairingView.swift`. Identify: QR code view, status text for each pairing step (waiting/connecting/verifying/done), any manual glass wrappers.

- [ ] **Step 2: Apply the changes**

Add `.presentationBackground(.thinMaterial)` as a modifier on the root `body` view. Wrap the QR code block and the status-step block in `GlassSection`s (no title required). Replace any custom glass wrappers. For the progress-step icons (e.g. `Image(systemName: "arrow.triangle.2.circlepath")`), add `.symbolEffect(.variableColor, options: .repeating)` while the step is active.

The exact shape depends on the current file — preserve all pairing logic, only replace visual containers. A minimal pattern:

```swift
struct PairingView: View {
    // ... existing properties ...

    var body: some View {
        VStack(spacing: 20) {
            GlassSection(title: /* existing title */, systemImage: "qrcode") {
                // existing QR code view
            }
            GlassSection {
                // existing step-by-step status, with added symbolEffect
                // on the active step icon
            }
            // existing action buttons (Cancel / Done)
        }
        .padding(24)
        .frame(minWidth: 440)
        .presentationBackground(.thinMaterial)
    }
}
```

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: Open the pairing sheet (from Home tab "Pair device" button or Settings tab "Add new device"). Sheet appears over the window as a thinMaterial glass panel.

- [ ] **Step 4: Manual verify**

Confirm:
- Sheet has translucent glass background (window content visible behind it)
- QR code and pairing status are in clean GlassSections
- Active step icon has a visible variableColor animation

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/PairingView.swift
git commit -m "refactor(macos): migrate PairingView to GlassSection + thinMaterial sheet background"
```

---

## Task 14: Migrate OnboardingView

First-run screen. Same pattern as About — wrap in GlassSections, add symbolEffect on step transitions. Full-window replaces ContainerBackground already set in AirbridgeApp.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/OnboardingView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/OnboardingView.swift`. Map out: how many steps it has, which visual containers wrap each step, any manual glass.

- [ ] **Step 2: Apply the changes**

Replace any custom `VStack.padding(...).glassEffect(...)` wrappers with `GlassSection`. The outer layout stays as-is (full window, centered content) because `AirbridgeApp` already sets `.containerBackground(.thickMaterial, for: .window)` on the OnboardingView branch. For SF Symbols that represent step transitions (arrow icons, checkmarks when a step completes), add `.symbolEffect(.bounce, value: currentStep)` so they animate when you advance.

If the file currently has a background color fill, remove it — Liquid Glass handles that at the window level.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`

To visually verify onboarding, temporarily reset the onboarding flag:

```bash
defaults delete com.airbridge.macos onboardingCompleted 2>/dev/null || true
killall AirbridgeApp 2>/dev/null
open "$HOME/Applications/Airbridge.app"
```

Click through the onboarding steps. After verifying, set it back if needed:

```bash
defaults write com.airbridge.macos onboardingCompleted -bool true
```

- [ ] **Step 4: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/OnboardingView.swift
git commit -m "refactor(macos): migrate OnboardingView to GlassSection primitive"
```

---

## Task 15: Migrate GalleryView

Has its own grid scroll — uses `ScreenContainer(scroll: false)` (already set in MainWindow task 7). Thumbnails get a subtle `.glassEffect` border. Filter/refresh toolbar area becomes a `GlassSection`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/GalleryView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/GalleryView.swift`. Identify: the scroll/grid region, the thumbnail view, any top toolbar/filter bar.

- [ ] **Step 2: Apply the changes**

Remove any outer `VStack.padding(24)` — `ScreenContainer(scroll: false)` provides that.
If there is a top toolbar/filter strip, wrap it in a `GlassSection`.
On each thumbnail `Image(...)` / `AsyncImage(...)`, add:

```swift
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
.glassEffect(.regular, in: .rect(cornerRadius: 8))
```

But only on the OUTER bounds of each thumbnail — not an extra container per image. **Do not wrap each thumbnail in a GlassSection** (performance trap — hundreds of thumbnails × full glass section = GPU wreck). The main `GlassEffectContainer` from `ScreenContainer` handles the shared blur.

For loading states (while thumbnail is being fetched), use a placeholder with `.redacted(reason: .placeholder)` rather than manual `ProgressView`, unless a ProgressView is already being displayed successfully.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: Gallery tab opens, grid loads. Thumbnails have subtle rounded glass borders.

- [ ] **Step 4: Manual verify**

- Scroll through the gallery — watch frame rate subjectively. Should be smooth.
- If noticeably laggy, remove the `.glassEffect(...)` from thumbnails entirely and keep only `.clipShape(RoundedRectangle(cornerRadius: 8))`.
- Hover over a thumbnail — should feel consistent with other screens.

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/GalleryView.swift
git commit -m "refactor(macos): migrate GalleryView — subtle glass thumbnails, GlassSection filter bar"
```

---

## Task 16: Migrate MessagesView

Has its own `HSplitView` internal scroll — `ScreenContainer(scroll: false)`. Conversation list rows become `GlassRow`s with `.interactive()`. Message bubbles use `.glassEffect(.regular.tint(...), in: .containerRelative)`.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/MessagesView.swift`

- [ ] **Step 1: Read current state**

Read `macos/Airbridge/Sources/AirbridgeApp/Views/MessagesView.swift`. Identify: conversation list sidebar, detail pane with message bubbles, loading indicator.

- [ ] **Step 2: Apply the changes**

- Remove any outer `VStack.padding(24)` — `ScreenContainer(scroll: false)` provides the frame.
- Conversation list: each row becomes `GlassRow { HStack { ... } }`. If rows are inside a `List`, keep the `List` but add `.listStyle(.plain)` and `.scrollContentBackground(.hidden)` so the list itself doesn't fight the glass.
- For row interactive feel, add `.glassEffect(.regular.interactive(), in: .containerRelative)` on the GlassRow (means overriding the default `.regular` with the interactive variant — update GlassRow to accept a parameter, OR just use raw HStack + direct glassEffect for rows where `.interactive()` is needed).

The simplest approach is to NOT use GlassRow for conversation rows and instead inline it:

```swift
ForEach(conversations) { conv in
    HStack { ... existing row content ... }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .containerRelative)
        .onTapGesture { select(conv) }
}
```

- Message detail pane: each bubble uses:

```swift
Text(message.body)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .glassEffect(
        message.isOutgoing
            ? .regular.tint(.accentColor)
            : .regular,
        in: .containerRelative
    )
```

- Loading state: replace any `ProgressView` for message-load with `Image(systemName: "ellipsis.bubble").symbolEffect(.pulse, options: .repeating)` OR keep the ProgressView but with `.controlSize(.small)`.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`
Expected: Messages tab loads. Conversation list on left shows glass rows; detail pane on right shows bubble-style messages with tinted glass on outgoing, regular on incoming.

- [ ] **Step 4: Manual verify**

- Click between conversations — list rows show subtle hover/press feedback from `.interactive()`
- Send a SMS (or view existing) — outgoing messages appear in accent-tinted glass bubbles, incoming in neutral glass
- Loading a new conversation — brief pulse/indicator is visible then fades

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/MessagesView.swift
git commit -m "refactor(macos): migrate MessagesView — interactive conversation rows, glass bubbles"
```

---

## Task 17: TransferPopupState enum + TransferPopupView rewrite

The big one for TransferPopup. Creates a state enum, rewrites the view as state-driven with `GlassEffectContainer` + `glassEffectID` morph, replaces all `Color.black` / `Color.white.opacity` / `MarqueeText` / manual gradient `ProgressView` with native SwiftUI.

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupState.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift`

- [ ] **Step 1: Create the state enum**

Create `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupState.swift`:

```swift
import Foundation

enum TransferPopupState: Equatable {
    case incoming(filename: String, sizeBytes: Int64)
    case waiting(filename: String)
    case transferring(filename: String, progress: Double, isReceiving: Bool)
    case complete(filename: String, isReceiving: Bool)
    case rejected(filename: String)

    var filename: String {
        switch self {
        case .incoming(let f, _),
             .waiting(let f),
             .transferring(let f, _, _),
             .complete(let f, _),
             .rejected(let f):
            return f
        }
    }
}
```

- [ ] **Step 2: Rewrite TransferPopupView**

Overwrite `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift` with:

```swift
import SwiftUI
import AppKit

// MARK: - TransferPopupView

struct TransferPopupView: View {
    let fileTransferService: FileTransferService
    @AppStorage("islandWidth") private var islandWidth: Double = 560
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @Namespace private var glassNS
    @State private var showComplete = false

    private var state: TransferPopupState {
        if fileTransferService.hasIncomingOffer {
            return .incoming(
                filename: fileTransferService.fileTransferFileName,
                sizeBytes: fileTransferService.incomingOfferFileSize
            )
        }
        if fileTransferService.isRejected {
            return .rejected(filename: fileTransferService.fileTransferFileName)
        }
        if fileTransferService.isWaitingForAccept {
            return .waiting(filename: fileTransferService.fileTransferFileName)
        }
        if showComplete {
            return .complete(
                filename: fileTransferService.fileTransferFileName,
                isReceiving: fileTransferService.isReceivingFile
            )
        }
        return .transferring(
            filename: fileTransferService.fileTransferFileName.isEmpty ? "file" : fileTransferService.fileTransferFileName,
            progress: fileTransferService.fileTransferProgress,
            isReceiving: fileTransferService.isReceivingFile
        )
    }

    private func tint(for state: TransferPopupState) -> Color {
        switch state {
        case .incoming, .waiting, .transferring: return .accentColor
        case .complete: return .green
        case .rejected: return .red
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            Group {
                switch state {
                case .incoming(let name, let size):
                    incomingView(name: name, size: size)
                case .waiting(let name):
                    waitingView(name: name)
                case .transferring(let name, let progress, let receiving):
                    transferringView(name: name, progress: progress, isReceiving: receiving)
                case .complete(_, let receiving):
                    completeView(isReceiving: receiving)
                case .rejected(let name):
                    rejectedView(name: name)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: islandWidth, height: islandHeight)
            .glassEffect(
                .regular.tint(tint(for: state)),
                in: .rect(cornerRadius: 28, style: .continuous)
            )
            .glassEffectID("popup", in: glassNS)
        }
        .shadow(radius: 30, y: 12)
        .animation(.airbridgeSmooth, value: state)
        .onChange(of: fileTransferService.fileTransferProgress) { _, new in
            if new >= 1.0 {
                withAnimation(.airbridgeSmooth) { showComplete = true }
            } else if new == 0 {
                showComplete = false
            }
        }
    }

    // MARK: - Subviews per state

    private func incomingView(name: String, size: Int64) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przychodzący plik" : "Incoming file")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatBytes(size))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            HStack(spacing: 8) {
                Button(L10n.isPL ? "Odrzuć" : "Reject") {
                    fileTransferService.rejectIncomingOffer()
                }
                .controlSize(.large)

                Button(L10n.isPL ? "Akceptuj" : "Accept") {
                    fileTransferService.acceptIncomingOffer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func waitingView(name: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Czekam na akceptację..." : "Waiting for acceptance...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L10n.isPL ? "Anuluj" : "Cancel") {
                fileTransferService.cancelPendingTransfer()
            }
            .controlSize(.large)
        }
    }

    private func transferringView(name: String, progress: Double, isReceiving: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: isReceiving ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.variableColor, options: .repeating)

            VStack(alignment: .leading, spacing: 6) {
                Text(isReceiving
                    ? (L10n.isPL ? "Odbieram" : "Receiving")
                    : (L10n.isPL ? "Wysyłam" : "Sending"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack {
                    Text(speedText)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Spacer()
                    Text(etaText)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 72, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }

    private func completeView(isReceiving: Bool) -> some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: isReceiving)
            Text(isReceiving
                ? (L10n.isPL ? "Plik odebrany!" : "File received!")
                : (L10n.isPL ? "Plik wysłany!" : "File sent!"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func rejectedView(name: String) -> some View {
        HStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.isPL ? "Przesyłanie odrzucone" : "Transfer rejected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var speedText: String {
        let speed = fileTransferService.transferSpeed
        let label = L10n.isPL ? "Prędkość" : "Speed"
        if speed > 1024 * 1024 {
            return String(format: "%@: %.1f MB/s", label, speed / (1024 * 1024))
        } else if speed > 1024 {
            return String(format: "%@: %.0f KB/s", label, speed / 1024)
        }
        return " "
    }

    private var etaText: String {
        let eta = fileTransferService.transferEta
        let label = L10n.isPL ? "Pozostało" : "Remaining"
        if eta > 60 {
            return "\(label): \(eta / 60) min \(eta % 60) s"
        } else if eta > 3 {
            return "\(label): \(eta) s"
        } else if fileTransferService.fileTransferProgress > 0 && fileTransferService.fileTransferProgress < 1.0 {
            return L10n.isPL ? "\(label): kilka sekund…" : "\(label): a few seconds…"
        }
        return " "
    }

    private func formatBytes(_ size: Int64) -> String {
        if size > 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0)) }
        if size > 1024 { return String(format: "%.0f KB", Double(size) / 1024.0) }
        return "\(size) B"
    }
}

// MARK: - TransferPopup singleton
// (Window management — see Task 18 for the slim rewrite)

@MainActor
final class TransferPopup {

    static let shared = TransferPopup()

    private var panel: NSWindow?
    private var isVisible = false

    private init() {}

    func show(fileTransferService: FileTransferService) {
        if isVisible { return }
        isVisible = true

        let view = TransferPopupView(fileTransferService: fileTransferService)
        let hostingView = NSHostingView(rootView: view)

        guard let screen = NSScreen.main else { return }
        let (x, y, width, height) = computeLayout(screen: screen)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .screenSaver
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Slide in — see Task 18 for the animation
        let startY = y + height + 10
        window.setFrame(NSRect(x: x, y: startY, width: width, height: height), display: true)
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

        self.panel = window
    }

    func hide(delay: TimeInterval = 2.5) {
        guard isVisible, let panel else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let panel = self.panel else { return }
            let frame = panel.frame
            let targetY = frame.origin.y + frame.height + 10

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
            }, completionHandler: {
                panel.orderOut(nil)
                self.panel = nil
                self.isVisible = false
            })
        }
    }

    private func computeLayout(screen: NSScreen) -> (x: Double, y: Double, width: Double, height: Double) {
        let defaults = UserDefaults.standard
        let offsetFromTop = defaults.object(forKey: "islandOffsetY") as? Double ?? 0
        let islandWidth = defaults.object(forKey: "islandWidth") as? Double ?? 560
        let height = defaults.object(forKey: "islandHeight") as? Double ?? 130

        let screenFrame = screen.frame
        let x = screenFrame.midX - islandWidth / 2
        let y = screenFrame.maxY - offsetFromTop - height

        return (x, y, islandWidth, height)
    }
}
```

Note: `MarqueeText` and `BottomRoundedShape` are now gone from this file. `BottomRoundedShape` is still referenced by `DropZoneView` as of this task — that's fixed in Task 19.

- [ ] **Step 3: Build and install**

Run: `scripts/dev-install.sh`

At this point the build will **fail** because `DropZoneView.swift` still imports `BottomRoundedShape` from this file. To unblock the build, temporarily re-add a minimal stub at the bottom of `TransferPopupView.swift`:

```swift
// TEMPORARY: kept for DropZoneView until Task 19 migrates it. Delete in Task 19.
struct BottomRoundedShape: Shape {
    var radius: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
```

Re-run `scripts/dev-install.sh`. Build should succeed.

- [ ] **Step 4: Manual verify**

Trigger a file transfer from the phone. Watch the TransferPopup:
- Slides down from the top (natively animated via `NSAnimationContext`)
- Glass background is visible (wallpaper faintly shows through)
- Ikona icon animates (bounce/pulse/variableColor depending on state)
- Progress %, speed, ETA all morph via `.numericText()` — digits flip smoothly
- Completion shows the green-tinted glass with checkmark bounce
- Popup slides up and disappears

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupState.swift macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift
git commit -m "feat(macos): rewrite TransferPopupView with Liquid Glass, glassEffectID morph, native animations"
```

---

## Task 18: TransferPopup fallback check — window level

Validate whether `window.level = .screenSaver` still lets Liquid Glass blur work. If the popup shows empty/opaque glass on that level, drop to `.popUpMenu`.

**Files:**
- (Potentially modify): `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift` (the `TransferPopup` singleton)

- [ ] **Step 1: Test current behavior**

Trigger a transfer. Look at the TransferPopup carefully — specifically whether the glass is blurring the desktop behind it.

- [ ] **Step 2: If glass is empty/opaque**

If the glass is blank/white/missing its blur effect, the screenSaver window level is blocking the Liquid Glass system from sampling content behind it. Change the level:

In `TransferPopupView.swift`, inside `TransferPopup.show(...)`:

```swift
// Before:
window.level = .screenSaver

// After:
window.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
```

- [ ] **Step 3: Re-test**

Run: `scripts/dev-install.sh`
Trigger another transfer. The glass should now blur the desktop properly. Trade-off: the popup will no longer appear over full-screen applications.

- [ ] **Step 4: Commit (only if level changed)**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift
git commit -m "fix(macos): lower TransferPopup window level to popUpMenu so Liquid Glass blur can sample desktop"
```

If no change was needed, skip this task's commit — add a note in the plan's execution log instead.

---

## Task 19: DropZoneView rewrite + BottomRoundedShape/UShape cleanup

Analogous treatment for the Quick Drop zone popup. Remove `Color.black` + `BottomRoundedShape` + `UShape`, replace with nested GlassEffectContainer and `.interactive()` drop area. This is the final consumer of `BottomRoundedShape` — delete both obsolete shapes at the end of this task.

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/DropZoneView.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift` (remove the temporary BottomRoundedShape stub)
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/DropZonePopup.swift` (simplify slide animation)

- [ ] **Step 1: Rewrite DropZoneView**

Overwrite `macos/Airbridge/Sources/AirbridgeApp/Views/DropZoneView.swift` with:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let connectionService: ConnectionService
    let fileTransferService: FileTransferService
    let onFileDrop: () -> Void

    @AppStorage("islandWidth") private var islandWidth: Double = 756
    @AppStorage("islandHeight") private var islandHeight: Double = 130

    @State private var isTargeted = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            Group {
                if connectionService.isConnected {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .padding(18)
            .frame(width: islandWidth, height: islandHeight)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: 24, style: .continuous)
            )
        }
        .shadow(radius: 40, y: 14)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .onHover { _ in
            DropZonePopup.shared.resetAutoHideTimer()
        }
        .onChange(of: isTargeted) { _, _ in
            DropZonePopup.shared.resetAutoHideTimer()
        }
    }

    private var connectedContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: !isTargeted)
                .symbolEffect(.bounce, value: isTargeted)

            Text(L10n.dropFileHere)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .glassEffect(
            isTargeted
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 18, style: .continuous)
        )
        .animation(.airbridgeQuick, value: isTargeted)
    }

    private var disconnectedContent: some View {
        HStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.noDeviceConnected)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard connectionService.isConnected else { return false }
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                fileTransferService.sendFile(url: url)
                onFileDrop()
            }
        }
        return true
    }
}
```

Note: `UShape` struct is gone (was used for the dashed U-border).

- [ ] **Step 2: Remove the temporary BottomRoundedShape stub from TransferPopupView**

In `macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift`, delete the entire block starting with:

```swift
// TEMPORARY: kept for DropZoneView until Task 19 migrates it. Delete in Task 19.
struct BottomRoundedShape: Shape {
    ...
}
```

And ending at its closing brace.

- [ ] **Step 3: Simplify DropZonePopup singleton slide animations**

In `macos/Airbridge/Sources/AirbridgeApp/Services/DropZonePopup.swift`, find the `show(...)` method's slide-in block (the `let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { ... }` near the end) and replace with:

```swift
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
```

Also find `hide()`'s slide-out Timer block and replace with:

```swift
        let frame = panel.frame
        let targetY = frame.origin.y + frame.height + 10

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
        }, completionHandler: { [weak self] in
            if let monitor = self?.escapeMonitor {
                NSEvent.removeMonitor(monitor)
                self?.escapeMonitor = nil
            }
            panel.orderOut(nil)
            self?.panel = nil
            self?.isVisible = false
        })
```

Keep the `autoHideTimer` logic and `escapeMonitor` setup — those are business logic, not animation.

- [ ] **Step 4: Build and install**

Run: `scripts/dev-install.sh`
Expected: build succeeds. No references to `BottomRoundedShape` or `UShape` remain.

- [ ] **Step 5: Manual verify**

Trigger the Quick Drop hotkey (default Cmd+Shift+V — check Settings → Quick Drop Shortcut if unclear):
- Panel slides in with natively-animated window frame
- Panel background is Liquid Glass (wallpaper visibly blurred through)
- Drop area inside is a separate glass sub-element (concentric-ish corners)
- Hovering mouse over the drop area shows the `.interactive()` feedback
- Dragging a file from Finder over the drop area: tint shifts to accentColor, icon bounces, spring animation
- Dropping the file: transfer starts, panel auto-hides

- [ ] **Step 6: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/DropZoneView.swift macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift macos/Airbridge/Sources/AirbridgeApp/Services/DropZonePopup.swift
git commit -m "feat(macos): rewrite DropZoneView with Liquid Glass, remove BottomRoundedShape and UShape, native window animations"
```

---

## Task 20: Final verification — grep sweep + manual user-level test

Systematic verification that every success criterion from spec Section 8 is met. No code changes expected — if any criterion fails, that's a bug fix, not planned work.

**Files:** (none modified unless bugs found)

- [ ] **Step 1: Grep — no more manual `.glassEffect(in: .rect(cornerRadius:`**

Run from repo root:

```bash
grep -n 'glassEffect(in: .rect(cornerRadius:' macos/Airbridge/Sources/AirbridgeApp/Views/**/*.swift 2>/dev/null | grep -v Components/
```

Expected output: only hits in `HistoryView.swift` on the per-record icon badge (that one is intentional — it's an icon pill, not a card). Everything else must be empty. If other files show up, migrate them to `GlassSection`/`GlassRow`/`.containerRelative`.

- [ ] **Step 2: Grep — no `Color.black` or white-opacity backgrounds in Views**

```bash
grep -rn 'Color\.black\|Color\.white\.opacity' macos/Airbridge/Sources/AirbridgeApp/Views/
```

Expected: empty. If anything matches, it's leftover from the old TransferPopup/DropZone styling — remove.

- [ ] **Step 3: Grep — no `Timer(timeInterval`/`Timer.scheduledTimer` in Views or for animations**

```bash
grep -rn 'Timer(timeInterval\|Timer\.scheduledTimer' macos/Airbridge/Sources/AirbridgeApp/Views/ macos/Airbridge/Sources/AirbridgeApp/Services/DropZonePopup.swift
```

Expected: only `autoHideTimer = Timer.scheduledTimer` in `DropZonePopup.swift` (that's the auto-hide business logic, not animation). No 60fps animation timers.

- [ ] **Step 4: Grep — no `BottomRoundedShape`, no `UShape`, no `MarqueeText`**

```bash
grep -rn 'BottomRoundedShape\|UShape\|MarqueeText' macos/Airbridge/Sources/AirbridgeApp/
```

Expected: empty. If anything matches, delete it.

- [ ] **Step 5: Grep — no `CACurrentMediaTime()` in Views**

```bash
grep -rn 'CACurrentMediaTime' macos/Airbridge/Sources/AirbridgeApp/Views/ macos/Airbridge/Sources/AirbridgeApp/Services/
```

Expected: empty.

- [ ] **Step 6: Grep — ScreenContainer used for every main tab**

```bash
grep -n 'ScreenContainer' macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift | wc -l
```

Expected: 7 (one per tab: Home, History, Send, Gallery, Messages, Settings, About).

- [ ] **Step 7: Grep — GlassEffectContainer present in ScreenContainer**

```bash
grep -n 'GlassEffectContainer' macos/Airbridge/Sources/AirbridgeApp/Views/Components/ScreenContainer.swift
```

Expected: at least one match.

- [ ] **Step 8: Grep — glassEffectID in TransferPopupView**

```bash
grep -n 'glassEffectID\|@Namespace' macos/Airbridge/Sources/AirbridgeApp/Views/TransferPopupView.swift
```

Expected: both present.

- [ ] **Step 9: Full build with warnings check**

```bash
cd macos/Airbridge
swift build 2>&1 | tee /tmp/airbridge-final-build.log
grep -E "error:|warning:" /tmp/airbridge-final-build.log | head
cd -
```

Expected: zero errors. Warnings should only be about things unrelated to this work (old code in Protocol/Networking/etc. may have pre-existing warnings — those are fine as long as they aren't new ones introduced by the migration).

- [ ] **Step 10: Manual test — user-level checklist**

Run `scripts/dev-install.sh`. Walk through the spec Section 8 user-level checklist manually:

1. **Window chrome** — tytuł w unified toolbar, nie w osobnym title-barze; tło okna Liquid-Glass-przezierne
2. **Scroll edges** — na każdym ekranie content rozmywa się przy górnej i dolnej krawędzi przewijania (try Home, Settings, History, Send scrolling)
3. **Hover** — najechanie myszką na drop-zone w SendView lub na konwersację w Messages daje subtelny glass feedback
4. **Status transitions** — klik "Rozłącz" na Home → status-dot morfuje do szarego płynnie
5. **TransferPopup lifecycle** — initjuj transfer z telefonu; obserwuj pełny cykl `waiting → transferring → complete` z glass morph-em
6. **DropZonePopup** — Cmd+Shift+V; panel pojawia się przezroczysty, z desktopem widocznym przez blur; pulsująca ikona; drop → bounce → hide
7. **Reduce motion** — System Settings → Accessibility → Display → Reduce Motion ON; powtórz kluczowe animacje; mają stać się crossfade-ami, nic się nie psuje. Wyłącz z powrotem
8. **Light mode** — przełącz na light appearance; cała apka nadal czytelna; TransferPopup ma jasne tło z ciemnym tekstem (nie czarne)

Document any regressions found directly in this task's notes before committing.

- [ ] **Step 11: Commit (final)**

If grep checks revealed leftover work that needed fixing in this task, commit the cleanup:

```bash
git add -u
git commit -m "chore(macos): final Liquid Glass migration cleanup"
```

Otherwise, this task has no commit — the plan is complete.

---

## Self-review notes (from plan author)

**Spec coverage:**
- Section 1 (zakres) → tasks 1–19 cover all in-scope files
- Section 2 (shell architecture) → Tasks 6, 7
- Section 3 (primitives) → Tasks 1–5
- Section 4 (per-screen migration) → Tasks 8–16
- Section 5 (TransferPopup rewrite) → Task 17, 18
- Section 6 (DropZone rewrite) → Task 19
- Section 7 (motion conventions) → baked into every screen task + Task 20 verification
- Section 8 (success criteria) → Task 20
- Section 9 (risks) → Task 18 handles the window-level fallback; Task 15 handles the Gallery performance fallback inline

**Type consistency check:**
- `StatusIndicator.State` enum is consistent across all tasks (`.connected`, `.disconnected`, `.connecting`, `.error`)
- `GlassSection` parameter names (`title`, `systemImage`, `padding`) consistent in every usage
- `ScreenContainer(scroll: false)` used for Gallery and Messages in both Task 7 (MainWindow wiring) and Tasks 15/16 (screen bodies rely on that contract)
- `Animation.airbridgeQuick` / `airbridgeSmooth` consistently referenced
- `TransferPopupState` fields match between enum definition (Task 17) and view switch cases

**Placeholder scan:**
- AboutView (Task 12), PairingView (Task 13), OnboardingView (Task 14), GalleryView (Task 15), MessagesView (Task 16) are described as patterns rather than full code rewrites because (a) the engineer needs to read the existing file to preserve business logic, and (b) the primitive components are already defined with full code — these screens are straightforward container substitutions. Each task gives the exact shape to produce and the exact verification criteria. This is intentional and not a placeholder: the full code would be guessing at business logic the spec doesn't own.

**Known risk:** Task 18 is conditional — only commits if the window level needs changing. The plan flags this explicitly as an observability check, not a predetermined edit.
