# Files Browser — przeglądanie plików telefonu z Maca

**Data:** 2026-06-05
**Status:** Zatwierdzony design, do implementacji
**Branch bazowy:** mirror-mvp-plan-a (feature wejdzie na osobnym branchu)

## Cel

Dodać do aplikacji macOS przeglądarkę plików telefonu (Finder-like) z dwukierunkowym
transferem: nawigacja po folderach telefonu, podgląd, **ściąganie** plików na Maca i
**wgrywanie** plików z Maca do wybranego folderu na telefonie.

### Zakres (MVP)

- Przeglądanie folderów telefonu (Downloads, Documents, DCIM, WhatsApp itd.)
- Thumbnaile dla obrazów/wideo, ikony systemowe dla reszty (po typie/rozszerzeniu)
- Ściąganie plików na Maca (do `~/Downloads`)
- Wgrywanie plików z Maca do bieżącego folderu na telefonie (drag&drop z Findera)

### Poza zakresem (świadomie)

- Kasowanie / zmiana nazwy / przenoszenie plików na telefonie (to byłby pełny menedżer
  plików wymagający `MANAGE_EXTERNAL_STORAGE` — odrzucone ze względu na ryzyko i review).
- Dostęp do `Android/data` i `Android/obb` (limit Storage Access Framework).

## Decyzja architektoniczna: dostęp do plików przez SAF

Android dostaje dostęp do plików przez **Storage Access Framework — jednorazowy grant na
drzewo**. Przy pierwszym wejściu w „Pliki" telefon pokazuje systemowy picker
(`ACTION_OPEN_DOCUMENT_TREE`); użytkownik raz przyznaje dostęp do Pamięci wewnętrznej, apka
zapamiętuje grant (`takePersistableUriPermission`) i potem przegląda/czyta/zapisuje przez
`DocumentFile` w obrębie tego drzewa.

**Dlaczego SAF, nie `MANAGE_EXTERNAL_STORAGE`:** brak groźnego uprawnienia w manifeście,
przyjazne Play Store, pełna dwukierunkowość działa od ręki. Kompromis: jednorazowy grant do
kliknięcia + foldery `Android/data`/`Android/obb` poza zasięgiem (akceptowalne) + `DocumentFile`
odrobinę wolniejszy przy dużych katalogach (mitygowane cache'em documentId i paginacją).

## Architektura

Feature jest uogólnieniem istniejącego wzorca Galerii (Mac prosi → Android czyta z telefonu →
odsyła). Transfer plików (góra/dół) **reużywa istniejącej infrastruktury `FileTransferService`**
(binary chunks Android→Mac, HTTP pull Mac→Android) — nie budujemy drugiego silnika transferu.

```
macOS                                    Android
FilesBrowserView                         AirbridgeService.handleIncomingMessage()
  └─ FilesBrowserService (MessageHandler)   ├─ FilesListRequest   → FilesProvider.listDir()
       ↕ ConnectionService (WS JSON)        ├─ FileThumbnailRequest→ FilesProvider.getThumbnail()
       ↕ FileTransferService (binary/HTTP)  ├─ FileDownloadRequest → FilesProvider.openInputStream()
                                            └─ fileTransferOffer(destinationDir) → DocumentFile write
```

## Protokół — nowe wiadomości

Dodawane w `macos/.../Protocol/Message.swift` ORAZ
`android/.../protocol/Message.kt` (muszą być zsynchronizowane — Codable/JSON).

- `filesListRequest(path: String, page: Int, pageSize: Int)`
  - `path` względny do korzenia grantu (`""` = root); paginacja dla dużych folderów (pageSize ~200)
- `filesListResponse(path: String, entries: [FileEntry], totalCount: Int, page: Int, needsPermission: Bool)`
  - `FileEntry = { name: String, relativePath: String, isDirectory: Bool, size: Int64, modified: Int64 (epoch ms), mimeType: String }`
  - `needsPermission = true` gdy SAF jeszcze nie przyznany
- `fileThumbnailRequest(path: String)` / `fileThumbnailResponse(path: String, base64: String)`
  - tylko obrazy/wideo; reszta dostaje ikonę systemową po stronie Maca (bez round-tripu)
- `fileDownloadRequest(transferId: String, path: String)`
  - Android streamuje plik istniejącym kanałem binary chunk → Mac składa przez `FileAssembler`
- **Upload:** rozszerzamy istniejący `fileTransferOffer` o `destinationDir: String?`
  - `nil` = `~/Downloads` (zachowanie jak dziś); ustawione = zapis przez `DocumentFile` do tego folderu

## Android — `FilesProvider.kt` + grant SAF

- **Grant SAF:** w istniejącym wizardzie uprawnień (per-feature, osobne przyciski) dochodzi
  przycisk „Pliki" → `ACTION_OPEN_DOCUMENT_TREE` → `takePersistableUriPermission`; tree URI
  zapisany w SharedPreferences. **Zero nowych uprawnień w manifeście.**
- **`FilesProvider`** (nowy plik, obok `GalleryProvider`):
  - `listDir(relPath, page, pageSize)` przez `DocumentsContract.buildChildDocumentsUriUsingTree`,
    query kolumn `DOCUMENT_ID/DISPLAY_NAME/MIME_TYPE/SIZE/LAST_MODIFIED`; cache documentId per
    ścieżka dla wydajności nawigacji
  - `getThumbnail(relPath)` — reuse logiki skalowania/base64 z `GalleryProvider`
  - `openInputStream(relPath)` — download
  - `createFile(relPath, name) + OutputStream` — upload
- **Router:** nowe case'y w `AirbridgeService.handleIncomingMessage()` dla `FilesListRequest`,
  `FileThumbnailRequest`, `FileDownloadRequest` + obsługa `destinationDir` w gałęzi transferu

## macOS — `FilesBrowserService` + `FilesBrowserView`

- **`FilesBrowserService: MessageHandler`** (`@Observable @MainActor`, obok `GalleryService`):
  `currentPath`, `entries: [FileEntry]`, breadcrumb stack, `isLoading`, `needsPermission`,
  cache thumbnaili; metody `open(path)`, `navigateUp()`, `download(entry)`, `upload(urls)`
- **`FilesBrowserView`** (nowy plik): Finder-like
  - Pasek breadcrumb u góry (klikalne segmenty ścieżki)
  - Lista wpisów: ikony folderów + ikony plików po typie + thumbnaile obrazów (lazy, jak w Galerii)
  - Dwuklik folder → wejście; dwuklik pliku / przycisk → download na Maca
  - **Drag&drop z Findera na widok → upload do bieżącego folderu**
  - Progres góra/dół przez istniejący `TransferPopup` (island)
- **Rejestracja:** `AirbridgeApp.swift` (registerHandlers) + `ConnectionService.routeAuthenticatedMessage`
  (case'y nowych response'ów) + nowy `case files` w `NavigationItem` + `Tab(.files)` w `MainWindow`
  (ikona SF Symbol `folder`)

## Przepływy

**Browse:** tab Pliki → `filesListRequest("")`. Brak grantu → `needsPermission=true` → Mac
pokazuje empty-state „Przyznaj dostęp do plików na telefonie". Jest grant → render + lazy thumbnaile.

**Download:** zaznacz plik → `fileDownloadRequest(transferId, path)` → binary chunki → `~/Downloads`
+ island progresu.

**Upload:** przeciągnij pliki z Findera na folder → dla każdego `fileTransferOffer(destinationDir: currentPath)`
→ istniejący transfer → Android zapisuje przez `DocumentFile` do tego folderu.

## Obsługa błędów

- `needsPermission` → dedykowany empty-state z instrukcją przyznania dostępu na telefonie
- Ścieżka nieczytelna/nieistniejąca → błąd inline, zostajemy w poprzednim folderze
- Duży folder → paginacja (pageSize ~200)
- Błędy transferu góra/dół → istniejąca obsługa `FileTransferService`

## Testy

- **Android (unit):** `FilesProvider` — rozwiązywanie ścieżek względnych + mapowanie listingu
  `DocumentsContract` na `FileEntry` (fake tree)
- **Protokół (round-trip):** enkodowanie/dekodowanie nowych wiadomości po obu stronach
  (Swift Codable + Kotlin JSON), zsynchronizowane pola
- **Manualnie:** build → install → grant SAF → browse → download → upload na Z Fold 7 (serial RFCY71BEL0T)

## Punkty wpięcia (z mapy kodu)

| Warstwa | Plik |
|---|---|
| Protokół | `macos/.../Protocol/Message.swift`, `android/.../protocol/Message.kt` |
| Android handler | `android/.../service/AirbridgeService.kt` (`handleIncomingMessage`) |
| Android provider | `android/.../gallery/FilesProvider.kt` (nowy) |
| macOS service | `macos/.../Services/FilesBrowserService.swift` (nowy) |
| macOS routing | `macos/.../Services/ConnectionService.swift` (`routeAuthenticatedMessage`), `AirbridgeApp.swift` |
| macOS nawigacja | `macos/.../Navigation/NavigationItem.swift`, `MainWindow.swift` |
| macOS view | `macos/.../Views/FilesBrowserView.swift` (nowy) |
