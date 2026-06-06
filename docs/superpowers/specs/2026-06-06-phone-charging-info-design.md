# Telefon: stan i czas ładowania na macOS

**Data:** 2026-06-06
**Status:** zaakceptowany design
**Branch:** kontynuacja gałęzi roboczej tej sesji (`feat/files-search-sort-view`); merge/rozdzielenie do ustalenia przy domykaniu

## Cel

macOS pokazuje w `HomeView`, czy telefon się ładuje, oraz przewidywany czas do pełnego
naładowania (gdy system Androida go udostępnia). Dziś `DeviceInfo` telefonu niesie tylko
`batteryPercent` — bez stanu ładowania i czasu.

## Ograniczenie (świadomie zaakceptowane)

Czas pochodzi z `BatteryManager.computeChargeTimeRemaining()` (estymata AOSP). Bywa
niedostępny (`-1`) i może różnić się od wartości pokazywanej przez Samsung One UI (Samsung ma
własną estymatę bez publicznego API). Dlatego: zawsze pokazujemy **stan** ładowania (pewny),
a **czas** tylko gdy API zwróci wartość ≥ 0.

## 1. Protokół — `DeviceInfo` + 2 pola

Kotlin (`protocol/Message.kt`) i Swift (`Protocol/Message.swift`), backward-compatible
(defaulty dla starych klientów, czytane przez `opt*` / `decodeIfPresent`):

| pole | typ | default | znaczenie |
|------|-----|---------|-----------|
| `batteryCharging` | Boolean / Bool | `false` | czy telefon się ładuje |
| `chargeTimeRemainingMs` | Long / Int64 | `-1` | ms do pełna; `-1` = nieznany / nie dotyczy |

JSON keys: `battery_charging`, `charge_time_remaining_ms`. Serializacja `DeviceInfo` w
`DeviceInfoResponse.toJson` / dekodowanie w `fromJson` (Kotlin) oraz `DeviceInfo` Codable (Swift).

## 2. Android — `DeviceInfoProvider.collect`

- `batteryCharging` ← `batteryManager.isCharging` (API 23+; minSdk projektu to spełnia).
- `chargeTimeRemainingMs` ← gdy `Build.VERSION.SDK_INT >= 28` i ładuje:
  `batteryManager.computeChargeTimeRemaining()` (zwraca ms lub `-1`). Inaczej `-1`.
- Pozostałe pola `DeviceInfo` bez zmian.

## 3. macOS — odświeżanie na żywo (polling)

Dziś `deviceInfoRequest` jest wysyłany raz po auth (`ConnectionService`), więc stan ładowania
by „zamarzł". Dodajemy polling `deviceInfoRequest` co **10 s** gdy połączony (bateria zmienia
się wolno). Wzorzec jak istniejący polling `MacInfo` (Android `MainScreen` pętla `while
connected { … delay }`). Implementacja po stronie macOS: pętla/timer aktywny gdy
`connectionService.isConnected`, wysyłający `broadcast(.deviceInfoRequest)`; zatrzymywany po
rozłączeniu. Pojedynczy initial request po auth zostaje.

## 4. macOS — UI w `HomeView`

- **Battery pill** (`batteryPill` na `phonePreview`): gdy `batteryCharging == true` użyj ikony
  z piorunem (`battery.100percent.bolt`, dobranej do poziomu naładowania jak obecny
  `batterySymbol`, wariant `.bolt`) zamiast zwykłej. Tekst `%` bez zmian.
- **Kolumna info** (`deviceInfoColumn`): nowy wiersz „Zasilanie" / "Power":
  - ładuje się + czas ≥ 0 → „Ładowanie · ~1 godz. 20 min do pełna" / "Charging · ~1 hr 20 min to full"
  - ładuje się + czas `-1` → „Ładowanie" / "Charging"
  - nie ładuje → „Na baterii" / "On battery"
- **`formatChargeTime(ms)`** — czysta, testowalna funkcja (osobna, nie metoda widoku):
  - `< 60 min` → „45 min"
  - pełne godziny → „2 godz."
  - godziny+minuty → „1 godz. 20 min"
  - (angielska wersja: „45 min" / "2 hr" / "1 hr 20 min")
  - wejście ≤ 0 → traktowane przez wywołującego jako „brak czasu" (funkcja zakłada > 0).

## Testy

- Round-trip protokołu `DeviceInfo`/`DeviceInfoResponse` z nowymi polami (Kotlin
  `MessageTest`/odpowiedni, Swift `MessageTests`), w tym legacy-defaults (stary JSON bez pól →
  `false` / `-1`).
- `formatChargeTime`: < godziny, pełne godziny, godziny+minuty (oba języki kluczowych przypadków).
- `DeviceInfoProvider` (BatteryManager) i UI — weryfikacja ręczna e2e (jak dotąd).

## Poza zakresem (YAGNI)

Rozróżnianie źródła zasilania (AC/USB/Wireless), czas pracy na baterii przy rozładowywaniu,
historia/wykres baterii, powiadomienia o naładowaniu. Do ewentualnego dołożenia później.

## Pliki dotknięte

- `android/.../protocol/Message.kt` — `DeviceInfo` + 2 pola, serializacja w `DeviceInfoResponse`.
- `android/.../device/DeviceInfoProvider.kt` — odczyt charging + charge time.
- macOS Swift `Protocol/Message.swift` — `DeviceInfo` Codable + 2 pola.
- `macos/.../Services/ConnectionService.swift` — polling `deviceInfoRequest` co 10 s.
- `macos/.../Views/HomeView.swift` — battery pill (bolt), wiersz „Zasilanie", `formatChargeTime`.
- Testy: protokół (Kotlin+Swift), `formatChargeTime`.
