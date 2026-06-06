# Files browser — upload bez nadpisywania + usuwanie

**Data:** 2026-06-06
**Status:** zaakceptowany design
**Branch:** kontynuacja na `feat/files-search-sort-view` (spójny zestaw ulepszeń zakładki plików)

## Cel

Dwa powiązane usprawnienia zakładki plików (macOS przegląda pliki telefonu przez WebSocket):

1. **Upload bez nadpisywania** — gdy wgrywany plik ma nazwę istniejącego, telefon zapisuje
   kopię `nazwa (1).ext` zamiast po cichu nadpisywać. (Obecnie `createFile` →
   `FileOutputStream` truncuje istniejący plik.)
2. **Usuwanie** — możliwość skasowania pliku lub folderu (rekurencyjnie) z poziomu macOS,
   z dialogiem potwierdzenia. Usuwanie jest **trwałe** (telefon nie ma kosza dla `/sdcard`).

## Część A — Upload bez nadpisywania (tylko Android)

- Wyodrębniona **czysta, testowalna funkcja** `dedupedName(name: String, exists: (String) -> Boolean): String`:
  - jeśli `exists(name)` false → zwraca `name` bez zmian;
  - inaczej próbuje `base (1).ext`, `base (2).ext`, … aż `exists(candidate)` zwróci false;
  - numer wstawiany **przed rozszerzeniem**: `foto.jpg` → `foto (1).jpg`;
  - plik bez rozszerzenia: `nazwa` → `nazwa (1)`;
  - rozbicie base/ext: `substringBeforeLast('.')` / `substringAfterLast('.', "")` (pusty ext = brak kropki).
- `FilesProvider.createFile(relDir, name, mimeType)` używa `dedupedName(name) { File(dir, it).exists() }`
  do wyboru wolnej nazwy, a `FileOutputStream` otwiera już na tej nazwie. Zwracane `Uri`
  wskazuje nową nazwę (caller już używa zwróconego `Uri`).
- **Zero zmian w protokole.** macOS po `reload` zobaczy `foto (1).jpg`.

## Część B — Usuwanie (pełny stack)

### 1. Protokół (Kotlin `Message.kt` + Swift `Message.swift`)

- `FileDeleteRequest(path: String)` — `type: "file_delete_request"`.
- `FileDeleteResponse(path: String, success: Boolean, error: String?)` — `type: "file_delete_response"`,
  `error` opcjonalne (pomijane gdy null, jak istniejący `error` w SmsSendResponse).

### 2. Android `FilesProvider.delete(relPath): Boolean`

- `File(root, relPath)`; katalog → `deleteRecursively()`, plik → `delete()`. Zwraca wynik.
- **Guard:** `relPath.isBlank()` → zwróć `false` (nie kasujemy korzenia `/sdcard`).
- Nieistniejący plik → `false`.

### 3. Handler `AirbridgeService`

- `is Message.FileDeleteRequest` → `serviceScope.launch`: jeśli `!hasGrant()` → `FileDeleteResponse(path, false, "no_permission")`;
  inaczej `val ok = filesProvider.delete(message.path)` → `FileDeleteResponse(path, ok, if (ok) null else "delete_failed")`.

### 4. macOS `FilesBrowserService`

- `func delete(_ entry: FileEntry)` → `broadcast(.fileDeleteRequest(path: entry.relativePath))`.
- W `handleMessage`: `case .fileDeleteResponse(let path, let success, _)` → jeśli `success` `reload()`;
  inaczej ustaw `deleteError` (komunikat dla UI).
- Stan: `var deleteError: String?` (czyszczony przy nowej akcji / zamknięciu alertu).

### 5. macOS UI `FilesBrowserView`

- `@State private var entryPendingDeletion: FileEntry?`.
- `.contextMenu` na `FileRow` (lista) i `FileGridCell` (siatka): pozycja „Usuń" / "Delete"
  (`role: .destructive`) → ustawia `entryPendingDeletion = entry`.
- `.alert` (prezentowany gdy `entryPendingDeletion != nil`): tytuł „Usunąć *nazwa*?",
  treść „Tej operacji nie można cofnąć.", przyciski **Usuń** (`.destructive` → `filesBrowserService.delete(entry)`)
  i **Anuluj** (`.cancel`).
- Opcjonalnie drugi `.alert` na `deleteError` (błąd usuwania).
- Przekazanie akcji do prywatnych struktur wierszy/kafelków: closure `onDelete: (FileEntry) -> Void`
  ustawiane w `listView`/`gridView`.

## Testy

- Round-trip protokołu: `FileDeleteRequest`/`FileDeleteResponse` po stronie Kotlin (`FilesMessageTest.kt`)
  i Swift (`FilesMessageTests.swift`), w tym `error == nil` i `error != nil`.
- Czysta funkcja `dedupedName`: brak kolizji, jedna kolizja → `(1)`, łańcuch kolizji → `(2)`,
  plik bez rozszerzenia, plik z wieloma kropkami (`a.tar.gz` → `a.tar (1).gz`).
- `createFile`/`delete` (filesystem + `Environment` root) — weryfikacja ręczna e2e (jak `searchDir`).

## Poza zakresem (YAGNI)

Rename, masowe usuwanie, kosz/undo, opcja „nadpisz zamiast kopii". Do ewentualnego dołożenia później.

## Pliki dotknięte

- `android/.../protocol/Message.kt` — `FileDeleteRequest`/`FileDeleteResponse`.
- `android/.../files/FilesProvider.kt` — `dedupedName`, `createFile` (dedup), `delete`.
- `android/.../service/AirbridgeService.kt` — handler `FileDeleteRequest`.
- macOS Swift `Protocol/Message.swift` — `fileDeleteRequest`/`fileDeleteResponse`.
- `macos/.../Services/FilesBrowserService.swift` — `delete`, obsługa response, `deleteError`.
- `macos/.../Views/FilesBrowserView.swift` — context menu, alert potwierdzenia.
- Testy: `FilesMessageTest.kt`, `FilesMessageTests.swift`, nowy `FileDedupTest.kt`.
