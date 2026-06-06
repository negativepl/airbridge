# Phone Charging Info Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pokazać na macOS (HomeView) czy telefon się ładuje oraz przewidywany czas do pełnego naładowania (gdy Android go zna), odświeżane na żywo.

**Architecture:** `DeviceInfo` zyskuje `batteryCharging` + `chargeTimeRemainingMs` (Kotlin+Swift, backward-compatible). Android `DeviceInfoProvider` czyta je z `BatteryManager`. macOS pobiera `DeviceInfo` cyklicznie (polling co 10 s z HomeView) i renderuje stan + czas (czysta funkcja `formatChargeTime` w module Protocol).

**Tech Stack:** Kotlin (org.json, BatteryManager, JUnit), Swift (Codable, SwiftUI, XCTest). Testy: Kotlin `./gradlew :app:testDebugUnitTest`, Swift `swift test`.

---

## File Structure

- `android/.../protocol/Message.kt` — `DeviceInfo` +2 pola; `DeviceInfoResponse.toJson` serializuje je.
- `android/.../device/DeviceInfoProvider.kt` — odczyt `isCharging` + `computeChargeTimeRemaining`.
- macOS Swift `Protocol/Message.swift` — `DeviceInfo` +2 pola, custom `init(from:)` (backward-compat).
- macOS Swift `Protocol/ChargeTime.swift` (NOWY) — czysta `formatChargeTime(_:isPL:)`.
- `macos/.../Services/ConnectionService.swift` — `func requestDeviceInfo()`.
- `macos/.../Views/HomeView.swift` — polling `.task`, battery pill (bolt), wiersz „Zasilanie".
- Testy: `MessageTest.kt` (Kotlin toJson), `MessageTests.swift` (Swift round-trip+legacy), `ChargeTimeTests.swift` (NOWY, w ProtocolTests).

**Kolejność:** protokół (Kotlin, Swift) → formatChargeTime → Android provider → polling → UI.

---

## Task 1: Protokół Kotlin — `DeviceInfo` +2 pola

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` — `DeviceInfo` data class (~lines 44-55) + `DeviceInfoResponse.toJson` (~lines 595-613)
- Test: `android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt`

Note: Kotlin `fromJson` has no `device_info_response` case (the phone sends it, never receives it), so the test verifies the serialized JSON keys rather than a full round-trip.

- [ ] **Step 1: Add failing test** — append to `MessageTest.kt`:

```kotlin
    @Test fun deviceInfoResponseIncludesChargingFields() {
        val info = DeviceInfo(
            name = "Galaxy", model = "SM", manufacturer = "Samsung",
            androidVersion = "16", sdkInt = 34,
            totalStorageBytes = 1, freeStorageBytes = 1,
            totalRamBytes = 1, freeRamBytes = 1, batteryPercent = 80,
            batteryCharging = true, chargeTimeRemainingMs = 4_800_000
        )
        val json = org.json.JSONObject(Message.DeviceInfoResponse(info).toJson())
        val obj = json.getJSONObject("info")
        assertEquals(true, obj.getBoolean("battery_charging"))
        assertEquals(4_800_000L, obj.getLong("charge_time_remaining_ms"))
    }
```

- [ ] **Step 2: Run, verify FAIL (compile — DeviceInfo has no such params):**
`cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.MessageTest"`

- [ ] **Step 3: Add the two fields to `DeviceInfo` data class** (replace the class, ~lines 44-55):

```kotlin
data class DeviceInfo(
    val name: String,
    val model: String,
    val manufacturer: String,
    val androidVersion: String,
    val sdkInt: Int,
    val totalStorageBytes: Long,
    val freeStorageBytes: Long,
    val totalRamBytes: Long,
    val freeRamBytes: Long,
    val batteryPercent: Int,
    val batteryCharging: Boolean = false,
    val chargeTimeRemainingMs: Long = -1
)
```

- [ ] **Step 4: Serialize them in `DeviceInfoResponse.toJson`** — inside the `put("info", JSONObject().apply { ... })` block, after `put("battery_percent", info.batteryPercent)`, add:

```kotlin
                put("battery_charging", info.batteryCharging)
                put("charge_time_remaining_ms", info.chargeTimeRemainingMs)
```

- [ ] **Step 5: Run, verify PASS:**
`cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.MessageTest"`

- [ ] **Step 6: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt android/Airbridge/app/src/test/java/com/airbridge/protocol/MessageTest.kt
git commit -m "feat(android-protocol): DeviceInfo battery charging fields"
```

---

## Task 2: Protokół Swift — `DeviceInfo` +2 pola + backward-compat decode

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift` — `DeviceInfo` struct (~lines 195-230): fields, CodingKeys, memberwise init, add custom `init(from:)`.
- Test: `macos/Airbridge/Tests/ProtocolTests/MessageTests.swift`

- [ ] **Step 1: Add failing tests** — append to `MessageTests.swift` (it has a `roundTrip` helper like FilesMessageTests; if not, build the encode/decode inline):

```swift
    func testDeviceInfoChargingRoundTrip() throws {
        let info = DeviceInfo(name: "Galaxy", model: "SM", manufacturer: "Samsung",
                              androidVersion: "16", sdkInt: 34,
                              totalStorageBytes: 1, freeStorageBytes: 1,
                              totalRamBytes: 1, freeRamBytes: 1, batteryPercent: 80,
                              batteryCharging: true, chargeTimeRemainingMs: 4_800_000)
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(DeviceInfo.self, from: data)
        XCTAssertEqual(decoded.batteryCharging, true)
        XCTAssertEqual(decoded.chargeTimeRemainingMs, 4_800_000)
    }

    func testDeviceInfoLegacyDecodeDefaults() throws {
        // Old phone JSON without the new fields → defaults (false / -1).
        let legacy = #"""
        {"name":"G","model":"M","manufacturer":"S","android_version":"16","sdk_int":34,"total_storage_bytes":1,"free_storage_bytes":1,"total_ram_bytes":1,"free_ram_bytes":1,"battery_percent":80}
        """#
        let decoded = try JSONDecoder().decode(DeviceInfo.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.batteryCharging, false)
        XCTAssertEqual(decoded.chargeTimeRemainingMs, -1)
    }
```

- [ ] **Step 2: Run, verify FAIL:** `cd macos/Airbridge && swift test --filter MessageTests`

- [ ] **Step 3: Add the two fields** to the `DeviceInfo` struct (after `public let batteryPercent: Int`):

```swift
    public let batteryCharging: Bool
    public let chargeTimeRemainingMs: Int64
```

- [ ] **Step 4: Add the two CodingKeys** (after `case batteryPercent = "battery_percent"`):

```swift
        case batteryCharging      = "battery_charging"
        case chargeTimeRemainingMs = "charge_time_remaining_ms"
```

- [ ] **Step 5: Extend the memberwise `init`** — add the two params (with defaults) and assignments. Replace the existing `public init(...)` with:

```swift
    public init(name: String, model: String, manufacturer: String, androidVersion: String, sdkInt: Int, totalStorageBytes: Int64, freeStorageBytes: Int64, totalRamBytes: Int64, freeRamBytes: Int64, batteryPercent: Int, batteryCharging: Bool = false, chargeTimeRemainingMs: Int64 = -1) {
        self.name = name
        self.model = model
        self.manufacturer = manufacturer
        self.androidVersion = androidVersion
        self.sdkInt = sdkInt
        self.totalStorageBytes = totalStorageBytes
        self.freeStorageBytes = freeStorageBytes
        self.totalRamBytes = totalRamBytes
        self.freeRamBytes = freeRamBytes
        self.batteryPercent = batteryPercent
        self.batteryCharging = batteryCharging
        self.chargeTimeRemainingMs = chargeTimeRemainingMs
    }
```

- [ ] **Step 6: Add a custom `init(from:)`** for backward-compatible decoding (new fields optional → defaults). Add right after the memberwise init, inside the struct:

```swift
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        model = try c.decode(String.self, forKey: .model)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        androidVersion = try c.decode(String.self, forKey: .androidVersion)
        sdkInt = try c.decode(Int.self, forKey: .sdkInt)
        totalStorageBytes = try c.decode(Int64.self, forKey: .totalStorageBytes)
        freeStorageBytes = try c.decode(Int64.self, forKey: .freeStorageBytes)
        totalRamBytes = try c.decode(Int64.self, forKey: .totalRamBytes)
        freeRamBytes = try c.decode(Int64.self, forKey: .freeRamBytes)
        batteryPercent = try c.decode(Int.self, forKey: .batteryPercent)
        batteryCharging = try c.decodeIfPresent(Bool.self, forKey: .batteryCharging) ?? false
        chargeTimeRemainingMs = try c.decodeIfPresent(Int64.self, forKey: .chargeTimeRemainingMs) ?? -1
    }
```

Note: `encode(to:)` stays synthesized (we only added a custom `init(from:)`), so it will encode all fields including the two new ones — the round-trip test relies on that.

- [ ] **Step 7: Run, verify PASS:** `cd macos/Airbridge && swift test --filter MessageTests`

- [ ] **Step 8: Commit:**
```bash
git add macos/Airbridge/Sources/Protocol/Message.swift macos/Airbridge/Tests/ProtocolTests/MessageTests.swift
git commit -m "feat(macos-protocol): DeviceInfo charging fields + legacy decode"
```

---

## Task 3: `formatChargeTime` — czysta funkcja w module Protocol

**Files:**
- Create: `macos/Airbridge/Sources/Protocol/ChargeTime.swift`
- Test: `macos/Airbridge/Tests/ProtocolTests/ChargeTimeTests.swift` (create)

- [ ] **Step 1: Create failing test** `ChargeTimeTests.swift`:

```swift
import XCTest
@testable import Protocol

final class ChargeTimeTests: XCTestCase {
    func testMinutesOnlyPL() {
        XCTAssertEqual(formatChargeTime(45 * 60_000, isPL: true), "45 min")
    }
    func testWholeHoursPL() {
        XCTAssertEqual(formatChargeTime(2 * 3_600_000, isPL: true), "2 godz.")
    }
    func testHoursAndMinutesPL() {
        XCTAssertEqual(formatChargeTime(80 * 60_000, isPL: true), "1 godz. 20 min")
    }
    func testHoursAndMinutesEN() {
        XCTAssertEqual(formatChargeTime(80 * 60_000, isPL: false), "1 hr 20 min")
    }
    func testMinutesOnlyEN() {
        XCTAssertEqual(formatChargeTime(45 * 60_000, isPL: false), "45 min")
    }
    func testWholeHoursEN() {
        XCTAssertEqual(formatChargeTime(2 * 3_600_000, isPL: false), "2 hr")
    }
}
```

- [ ] **Step 2: Run, verify FAIL:** `cd macos/Airbridge && swift test --filter ChargeTimeTests`

- [ ] **Step 3: Create** `macos/Airbridge/Sources/Protocol/ChargeTime.swift`:

```swift
import Foundation

/// Formatuje pozostały czas ładowania (ms) na krótki tekst.
/// Zakłada `ms > 0` — wywołujący sam decyduje, że przy `<= 0` czasu nie pokazuje.
/// PL: „45 min" / „2 godz." / „1 godz. 20 min";  EN: "45 min" / "2 hr" / "1 hr 20 min".
public func formatChargeTime(_ ms: Int64, isPL: Bool) -> String {
    let totalMinutes = Int(ms / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    let hourUnit = isPL ? "godz." : "hr"
    if hours == 0 {
        return "\(minutes) min"
    }
    if minutes == 0 {
        return "\(hours) \(hourUnit)"
    }
    return "\(hours) \(hourUnit) \(minutes) min"
}
```

- [ ] **Step 4: Run, verify PASS (6 tests):** `cd macos/Airbridge && swift test --filter ChargeTimeTests`

- [ ] **Step 5: Commit:**
```bash
git add macos/Airbridge/Sources/Protocol/ChargeTime.swift macos/Airbridge/Tests/ProtocolTests/ChargeTimeTests.swift
git commit -m "feat(macos): pure formatChargeTime helper"
```

---

## Task 4: Android — `DeviceInfoProvider` czyta charging + czas

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/device/DeviceInfoProvider.kt`

- [ ] **Step 1: Read charging state + remaining time** — in `collect`, after the existing battery percent read (`val battery = bm.getIntProperty(...)`), add:

```kotlin
        val charging = bm.isCharging
        val chargeTimeMs: Long =
            if (charging && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // computeChargeTimeRemaining(): ms do pełna, lub -1 gdy nieznany.
                bm.computeChargeTimeRemaining()
            } else {
                -1L
            }
```

- [ ] **Step 2: Pass them into the `DeviceInfo(...)` constructor** — add the two args after `batteryPercent = battery`:

```kotlin
            batteryPercent = battery,
            batteryCharging = charging,
            chargeTimeRemainingMs = chargeTimeMs
```

(`Build` is already imported; `BatteryManager.isCharging` is API 23+, `computeChargeTimeRemaining` is API 28+ = `VERSION_CODES.P`.)

- [ ] **Step 3: Compile + tests:**
```bash
cd android/Airbridge && ./gradlew :app:compileDebugKotlin && ./gradlew :app:testDebugUnitTest
```
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/device/DeviceInfoProvider.kt
git commit -m "feat(android): collect battery charging state + time to full"
```

---

## Task 5: macOS — live polling `deviceInfoRequest`

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` — add a public `requestDeviceInfo()`.
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift` — `.task` polling loop.

- [ ] **Step 1: Add `requestDeviceInfo()` to ConnectionService** — near the auth block that already does `broadcast(.deviceInfoRequest)`. Add a method (anywhere in the class body):

```swift
    /// Poproś telefon o świeże DeviceInfo (np. cyklicznie, dla stanu ładowania na żywo).
    func requestDeviceInfo() {
        Task { try? await server.broadcast(.deviceInfoRequest) }
    }
```

- [ ] **Step 2: Add a polling `.task` to HomeView** — find the root view returned by `HomeView.body`. Add a `.task` modifier on it (alongside any existing modifiers):

```swift
        .task {
            // Odświeżaj DeviceInfo co 10 s, by stan/czas ładowania był na żywo.
            while !Task.isCancelled {
                if connectionService.isConnected {
                    connectionService.requestDeviceInfo()
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
```

Note: read HomeView to confirm the property is named `connectionService` (the view already reads `connectionService.isConnected` elsewhere — match that exact name). The `.task` is cancelled automatically when the view disappears, so polling only runs while Home is visible — acceptable since battery is only shown there.

- [ ] **Step 3: Build:** `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 4: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift
git commit -m "feat(macos): poll device info every 10s for live charging state"
```

---

## Task 6: macOS — UI: charging w battery pill + wiersz „Zasilanie"

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift`

- [ ] **Step 1: Show a bolt in the battery pill when charging.** The `batteryPill(_ percent:)` is called from `phonePreview`. Change the call site to pass charging, and update `batteryPill` to take it. First update the signature + body:

```swift
    private func batteryPill(_ percent: Int, charging: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: batterySymbol(percent))
            if charging {
                Image(systemName: "bolt.fill")
            }
            Text("\(percent)%")
                .contentTransition(.numericText())
        }
        .font(.ab(.caption2, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
```

- [ ] **Step 2: Update the `batteryPill` call site** in `phonePreview`. Read the current call (it passes only the percent, e.g. `batteryPill(info.batteryPercent)`); change it to:

```swift
                batteryPill(info.batteryPercent, charging: info.batteryCharging)
```

(If the call site uses a different local variable than `info`, match it — the DeviceInfo value in scope. If the pill is built where only a percent Int is in scope, thread the `DeviceInfo`/charging bool through to it.)

- [ ] **Step 3: Add a „Zasilanie" / "Power" row to `deviceInfoColumn`.** After the RAM `usageRow(...)` inside `deviceInfoColumn(_ info:)`, add:

```swift
            infoRow(L10n.isPL ? "Zasilanie" : "Power", Self.powerText(info))
```

- [ ] **Step 4: Add the `powerText` helper** — as a `static func` on the view (near `bytes(_:)` or other static helpers). It uses `formatChargeTime` from the Protocol module (already imported as `import Protocol` in HomeView — verify; if not, add it):

```swift
    private static func powerText(_ info: DeviceInfo) -> String {
        let isPL = L10n.isPL
        guard info.batteryCharging else {
            return isPL ? "Na baterii" : "On battery"
        }
        if info.chargeTimeRemainingMs > 0 {
            let t = formatChargeTime(info.chargeTimeRemainingMs, isPL: isPL)
            return isPL ? "Ładowanie · ~\(t) do pełna" : "Charging · ~\(t) to full"
        }
        return isPL ? "Ładowanie" : "Charging"
    }
```

- [ ] **Step 5: Build:** `cd macos/Airbridge && swift build`
Expected: Build complete. (Ignore SourceKit "No such module Protocol" false positives if swift build succeeds.)

- [ ] **Step 6: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/HomeView.swift
git commit -m "feat(macos): show phone charging state + time to full on Home"
```

---

## Task 7: Weryfikacja (ręczna e2e)

- [ ] **Step 1: Full tests:**
```bash
cd android/Airbridge && ./gradlew :app:testDebugUnitTest
cd ../../macos/Airbridge && swift test --filter ChargeTimeTests && swift test --filter MessageTests
```
Expected: PASS (Mirror integration failures are pre-existing and unrelated).

- [ ] **Step 2: Build + run apps:** Android `./gradlew :app:assembleDebug` + install; macOS `scripts/dev-install.sh`.

- [ ] **Step 3: Manual scenarios (phone connected, on Home screen):**
  - Podłącz ładowarkę do telefonu → w ciągu ~10 s battery pill na podglądzie pokazuje piorun, a wiersz „Zasilanie" pokazuje „Ładowanie" (i „~Xh Ym do pełna", jeśli telefon zna czas).
  - Odłącz ładowarkę → w ~10 s pill bez pioruna, wiersz „Na baterii".
  - Jeśli telefon (Samsung) zwraca `-1` dla czasu → pokazuje samo „Ładowanie" bez czasu (oczekiwane).

- [ ] **Step 4: Commit ewentualnych poprawek.**

---

## Self-Review

- **Spec coverage:** `batteryCharging`+`chargeTimeRemainingMs` w protokole, backward-compat (Task 1 toJson + Task 2 custom init z decodeIfPresent) ✓; Android odczyt `isCharging`+`computeChargeTimeRemaining` z guardem API 28 (Task 4) ✓; polling 10 s (Task 5) ✓; battery pill bolt + wiersz Zasilanie z formatChargeTime (Task 6) ✓; format czasu jako czysta testowalna funkcja (Task 3) ✓; obsługa `-1` → samo „Ładowanie" (Task 6 powerText) ✓.
- **Type consistency:** `batteryCharging: Boolean/Bool`, `chargeTimeRemainingMs: Long/Int64` spójne Kotlin↔Swift; `formatChargeTime(_ ms: Int64, isPL: Bool)` (Task 3) wywoływane w Task 6 z `info.chargeTimeRemainingMs`; `requestDeviceInfo()` (Task 5) ; `batteryPill(_:charging:)` (Task 6 Step 1↔2); `powerText(_ info: DeviceInfo)` (Task 6 Step 3↔4).
- **Placeholders:** brak — pełny kod i komendy w każdym kroku. Kroki, które wymagają dopasowania nazw lokalnych (call site batteryPill, nazwa property connectionService w HomeView), jawnie instruują „przeczytaj i dopasuj" zamiast zgadywać.
