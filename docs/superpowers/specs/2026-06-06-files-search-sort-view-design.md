# Files browser — wyszukiwarka, sortowanie, przełącznik widoku

**Data:** 2026-06-06
**Status:** zaakceptowany design

## Cel

Rozbudowa zakładki plików (macOS — `FilesBrowserView`, która przegląda pliki telefonu
przez WebSocket) o trzy funkcje:

1. **Wyszukiwarka** — globalne, rekurencyjne przeszukiwanie po nazwie od korzenia `/sdcard`.
2. **Sortowanie** — nazwa / rozmiar / data modyfikacji / typ, rosnąco/malejąco, z opcją „foldery pierwsze".
3. **Przełącznik widoku** — Lista ↔ Siatka.

Wyszukiwanie i sortowanie liczy **Android (serwer)** na całym katalogu; przełącznik widoku
to czysto UI macOS.

## Decyzje architektoniczne

- **Jeden endpoint** (nie osobny search request): rozszerzamy istniejący `FilesListRequest`
  o opcjonalne pola. Pusty `query` = normalne listowanie (obecne zachowanie). Niepusty `query`
  = rekurencyjny search. Odpowiedź to ten sam `FilesListResponse` — paginacja, thumbnaile i
  folder-stats działają bez zmian, bo `relativePath` już niesie pełną ścieżkę.
- **Backward-compatible**: nowe pola czytane przez `optString`/`optBoolean` z defaultami =
  dzisiejsze zachowanie, więc stary klient/serwer dalej działa.
- **Search globalny** — walk zawsze startuje od roota `""`, ignorując `currentPath`. Wyniki
  pokazują pełny `relativePath`. Po wyczyszczeniu pola wracamy do listingu bieżącego folderu.

## Protokół

`FilesListRequest` zyskuje 4 opcjonalne pola:

| pole          | typ                                          | default | znaczenie                          |
|---------------|----------------------------------------------|---------|------------------------------------|
| `sortBy`      | `"name"` \| `"size"` \| `"modified"` \| `"type"` | `name`  | klucz sortowania                   |
| `sortDir`     | `"asc"` \| `"desc"`                          | `asc`   | kierunek                           |
| `foldersFirst`| Bool                                         | `true`  | foldery zawsze na początku         |
| `query`       | String                                       | `""`    | fraza; niepusta → rekurencyjny search od roota |

Zmiany w `Message.kt` (Kotlin `toJson`/`fromJson`) oraz w Swift `Protocol` (Message enum +
`filesListRequest(...)`).

## Android — `FilesProvider`

- `listDir(relPath, page, pageSize, sortBy, sortDir, foldersFirst)` — komparator budowany
  dynamicznie:
  - `name` → `name.lowercase()`
  - `size` → `f.length()` (folder = 0; **płaski** rozmiar, NIE rekurencyjny — inaczej sort
    byłby zabójczo wolny; rekurencyjny rozmiar dalej leci osobno do podtytułu)
  - `modified` → `lastModified()`
  - `type` → rozszerzenie / mime
  - `foldersFirst` jako pierwszy klucz porównania (gdy włączone)
  - `sortDir` odwraca kolejność (oprócz klucza folders-first, który zostaje stabilny na górze)
- nowa `searchDir(query, page, pageSize, sortBy, sortDir, foldersFirst)` — `walkTopDown()` od
  roota, filtr `name.contains(query, ignoreCase=true)`, **early-stop po 500 wynikach**, potem
  sort i paginacja jak wyżej. Limit chroni przed zawieszeniem przy walku całego `/sdcard`.

## macOS — `FilesBrowserService`

- Nowy stan: `sortBy`, `sortDir`, `foldersFirst`, `searchQuery`.
- `sortBy` / `sortDir` / `foldersFirst` + tryb widoku persystowane przez `@AppStorage`
  (`searchQuery` nie persystowane).
- Zmiana sortowania lub query → `open(path:)` z nowymi parametrami, reset do strony 0.
- Search z **debounce ~300 ms** i minimum **2 znaki**.
- W trybie search `displayedEntries` **nie blokuje** na folder-stats (wyniki to mix z różnych
  ścieżek — pokazujemy od razu, podtytuł = `relativePath`).

## macOS — `FilesBrowserView`

- **Pasek narzędzi** nad listą: pole wyszukiwania (ikona lupy + przycisk czyszczenia),
  `Menu` sortowania (klucz + kierunek + toggle „foldery pierwsze"), segmentowany przełącznik
  **Lista ↔ Siatka**.
- **Grid**: `LazyVGrid` z większymi kafelkami — miniaturka (obraz/wideo) lub duża ikona typu
  + nazwa pod spodem. Te same gesty (double-click = `activate`), te same thumbnaile.
- W trybie search wiersz/kafelek pokazuje `relativePath` zamiast `name`.

## Poza zakresem (YAGNI)

- „Pokaż ukryte pliki", gęstość wierszy, zaznaczanie wielu plików, sortowanie zapamiętywane
  per-folder. Do ewentualnego dołożenia później.

## Pliki dotknięte

- `android/.../protocol/Message.kt` — nowe pola request.
- macOS Swift `Protocol` (Message enum + `filesListRequest`).
- `android/.../AirbridgeService.kt` — handler `files_list_request` przekazuje nowe parametry,
  rozgałęzia na `listDir` / `searchDir`.
- `android/.../files/FilesProvider.kt` — sort + `searchDir`.
- `macos/.../Services/FilesBrowserService.swift` — stan, debounce, persist.
- `macos/.../Views/FilesBrowserView.swift` — toolbar, grid, search field.
