# Files Search + Sort + View Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dodać do zakładki plików (macOS) globalną wyszukiwarkę, wybór sortowania i przełącznik widoku Lista↔Siatka; wyszukiwanie i sortowanie liczy Android na całym katalogu.

**Architecture:** Rozszerzamy istniejący `FilesListRequest` o 4 opcjonalne pola (`sortBy`, `sortDir`, `foldersFirst`, `query`) — pusty `query` = normalne listowanie, niepusty = rekurencyjny search od korzenia `/sdcard`. Odpowiedź to ten sam `FilesListResponse` (paginacja, thumbnaile, folder-stats bez zmian). Sortowanie po stronie Androida to czysta funkcja `sortFileEntries(...)` współdzielona przez `listDir` i `searchDir`. macOS dostaje stan sort/widok (persystowany w `@AppStorage`) i toolbar nad listą.

**Tech Stack:** Kotlin (org.json, JUnit), Swift (Codable, XCTest, SwiftUI), WebSocket. Testy: Kotlin `./gradlew :app:testDebugUnitTest`, Swift `swift test --filter ProtocolTests`.

---

## File Structure

- `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` — nowe pola w `FilesListRequest` (toJson/fromJson).
- `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt` — round-trip nowych pól + backward-compat.
- `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt` — czysta funkcja `sortFileEntries` + enumy, `listDir` z sortowaniem, nowa `searchDir`.
- `android/Airbridge/app/src/test/java/com/airbridge/files/FileSortTest.kt` — testy czystej funkcji sortowania.
- `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt` — handler `FilesListRequest` przekazuje nowe pola, rozgałęzia list/search.
- `macos/Airbridge/Sources/Protocol/Message.swift` — `filesListRequest` z 4 nowymi polami (enum case, encode, decode, CodingKeys).
- `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift` — round-trip nowych pól.
- `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift` — stan sort/search, `@AppStorage`, `open(...)` z parametrami, debounce, `displayedEntries` w trybie search.
- `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift` — toolbar (search field, sort menu, view toggle), widok siatki, `relativePath` w wynikach search.

**Kolejność:** protokół (Kotlin + Swift) → sortowanie Android → listDir/searchDir → handler → macOS service → macOS view. Warstwa protokołu pierwsza, bo wszystko inne na niej stoi.

---

## Task 1: Protokół Kotlin — nowe pola `FilesListRequest`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt:352-363` (data class + toJson) oraz `:747-751` (fromJson)
- Test: `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt`

- [ ] **Step 1: Dopisz failing testy round-trip**

Dodaj do `FilesMessageTest.kt` (po istniejącym `filesListRequestRoundTrip`):

```kotlin
    @Test fun filesListRequestSortSearchRoundTrip() {
        val msg = Message.FilesListRequest(
            path = "Download", page = 1, pageSize = 200,
            sortBy = "size", sortDir = "desc", foldersFirst = false, query = "raport"
        )
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListRequest
        assertEquals("size", parsed.sortBy)
        assertEquals("desc", parsed.sortDir)
        assertFalse(parsed.foldersFirst)
        assertEquals("raport", parsed.query)
    }

    @Test fun filesListRequestDefaultsWhenFieldsMissing() {
        // Stary klient: JSON bez nowych pól → defaulty = obecne zachowanie.
        val legacy = """{"type":"files_list_request","path":"","page":0,"page_size":200}"""
        val parsed = Message.fromJson(legacy) as Message.FilesListRequest
        assertEquals("name", parsed.sortBy)
        assertEquals("asc", parsed.sortDir)
        assertEquals(true, parsed.foldersFirst)
        assertEquals("", parsed.query)
    }
```

- [ ] **Step 2: Uruchom testy — mają NIE kompilować/failować**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: FAIL — kompilacja nie przejdzie (brak parametrów `sortBy` itd. w `FilesListRequest`).

- [ ] **Step 3: Rozszerz `FilesListRequest` (data class + toJson)**

Zamień blok `data class FilesListRequest` (linie ~352-363) na:

```kotlin
    data class FilesListRequest(
        val path: String,
        val page: Int,
        val pageSize: Int,
        val sortBy: String = "name",
        val sortDir: String = "asc",
        val foldersFirst: Boolean = true,
        val query: String = ""
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "files_list_request")
            put("path", path)
            put("page", page)
            put("page_size", pageSize)
            put("sort_by", sortBy)
            put("sort_dir", sortDir)
            put("folders_first", foldersFirst)
            put("query", query)
        }.toString()
    }
```

- [ ] **Step 4: Rozszerz deserializację `files_list_request`**

Zamień case `"files_list_request"` (linie ~747-751) na:

```kotlin
                "files_list_request" -> FilesListRequest(
                    path = obj.getString("path"),
                    page = obj.optInt("page", 0),
                    pageSize = obj.optInt("page_size", 200),
                    sortBy = obj.optString("sort_by", "name"),
                    sortDir = obj.optString("sort_dir", "asc"),
                    foldersFirst = obj.optBoolean("folders_first", true),
                    query = obj.optString("query", "")
                )
```

- [ ] **Step 5: Uruchom testy — mają przejść**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: PASS (wszystkie, łącznie ze starymi).

- [ ] **Step 6: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt \
        android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt
git commit -m "feat(android-protocol): sort+search fields on FilesListRequest"
```

---

## Task 2: Protokół Swift — nowe pola `filesListRequest`

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift` — case (`:45`), CodingKeys (`:332-376`), encode (`:484-488`), decode (`:738-742`)
- Test: `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift`

- [ ] **Step 1: Dopisz failing test round-trip**

Dodaj do `FilesMessageTests.swift`:

```swift
    func testFilesListRequestSortSearchRoundTrip() throws {
        let msg = Message.filesListRequest(path: "Download", page: 1, pageSize: 200,
                                           sortBy: "size", sortDir: "desc",
                                           foldersFirst: false, query: "raport")
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFilesListRequestDecodesLegacyWithDefaults() throws {
        let legacy = #"{"type":"files_list_request","path":"","page":0,"page_size":200}"#
        let decoded = try JSONDecoder().decode(Message.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded, .filesListRequest(path: "", page: 0, pageSize: 200,
                                                  sortBy: "name", sortDir: "asc",
                                                  foldersFirst: true, query: ""))
    }
```

- [ ] **Step 2: Uruchom — ma NIE kompilować**

Run: `cd macos/Airbridge && swift test --filter ProtocolTests`
Expected: FAIL — kompilacja: `filesListRequest` nie ma argumentów `sortBy` itd.

- [ ] **Step 3: Rozszerz enum case**

W `Message.swift:45` zamień:

```swift
    case filesListRequest(path: String, page: Int, pageSize: Int)
```

na:

```swift
    case filesListRequest(path: String, page: Int, pageSize: Int,
                          sortBy: String = "name", sortDir: String = "asc",
                          foldersFirst: Bool = true, query: String = "")
```

- [ ] **Step 4: Dodaj CodingKeys**

W bloku `private enum CodingKeys` (po `case pageSize = "page_size"`, linia ~352) dodaj:

```swift
        case sortBy             = "sort_by"
        case sortDir            = "sort_dir"
        case foldersFirst       = "folders_first"
        case query
```

- [ ] **Step 5: Rozszerz encode**

W `Message.swift:484-488` zamień case `.filesListRequest` w `encode(to:)` na:

```swift
        case .filesListRequest(let path, let page, let pageSize, let sortBy, let sortDir, let foldersFirst, let query):
            try container.encode(TypeKey.filesListRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)
            try container.encode(sortBy, forKey: .sortBy)
            try container.encode(sortDir, forKey: .sortDir)
            try container.encode(foldersFirst, forKey: .foldersFirst)
            try container.encode(query, forKey: .query)
```

- [ ] **Step 6: Rozszerz decode (z defaultami dla legacy)**

W `Message.swift:738-742` zamień case `.filesListRequest` w `init(from:)` na:

```swift
        case .filesListRequest:
            let path = try container.decode(String.self, forKey: .path)
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            let sortBy = try container.decodeIfPresent(String.self, forKey: .sortBy) ?? "name"
            let sortDir = try container.decodeIfPresent(String.self, forKey: .sortDir) ?? "asc"
            let foldersFirst = try container.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
            let query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
            self = .filesListRequest(path: path, page: page, pageSize: pageSize,
                                     sortBy: sortBy, sortDir: sortDir,
                                     foldersFirst: foldersFirst, query: query)
```

- [ ] **Step 7: Uruchom — ma przejść**

Run: `cd macos/Airbridge && swift test --filter ProtocolTests`
Expected: PASS (łącznie ze starym `testFilesListRequestRoundTrip` — `Equatable` uwzględni nowe pola, stary test używa domyślnych wartości więc dalej działa).

- [ ] **Step 8: Commit**

```bash
git add macos/Airbridge/Sources/Protocol/Message.swift \
        macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift
git commit -m "feat(macos-protocol): sort+search fields on filesListRequest"
```

---

## Task 3: Android — czysta funkcja `sortFileEntries`

Wyodrębniamy sortowanie do testowalnej funkcji bez filesystemu — współdzielonej przez `listDir` i `searchDir` (DRY).

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt` (dodaj top-level funkcję + enumy nad klasą)
- Test: `android/Airbridge/app/src/test/java/com/airbridge/files/FileSortTest.kt` (utwórz)

- [ ] **Step 1: Napisz failing testy**

Utwórz `android/Airbridge/app/src/test/java/com/airbridge/files/FileSortTest.kt`:

```kotlin
package com.airbridge.files

import com.airbridge.protocol.FileEntry
import org.junit.Assert.assertEquals
import org.junit.Test

class FileSortTest {
    private fun f(name: String, dir: Boolean = false, size: Long = 0, modified: Long = 0) =
        FileEntry(name, name, dir, size, modified, if (dir) "inode/directory" else "text/plain")

    private val sample = listOf(
        f("banana.txt", size = 30, modified = 200),
        f("Apple", dir = true, modified = 100),
        f("cherry.txt", size = 10, modified = 300),
        f("zebra", dir = true, modified = 50)
    )

    @Test fun nameAscFoldersFirst() {
        val r = sortFileEntries(sample, "name", "asc", foldersFirst = true).map { it.name }
        assertEquals(listOf("Apple", "zebra", "banana.txt", "cherry.txt"), r)
    }

    @Test fun nameDescFoldersFirst() {
        val r = sortFileEntries(sample, "name", "desc", foldersFirst = true).map { it.name }
        assertEquals(listOf("zebra", "Apple", "cherry.txt", "banana.txt"), r)
    }

    @Test fun sizeAscNoFoldersFirst() {
        // foldersFirst=false → czysto po rozmiarze; foldery (size 0) najpierw bo najmniejsze.
        val r = sortFileEntries(sample, "size", "asc", foldersFirst = false).map { it.name }
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }

    @Test fun modifiedDescFoldersFirst() {
        val r = sortFileEntries(sample, "modified", "desc", foldersFirst = true).map { it.name }
        // foldery najpierw (wg modified desc: Apple 100 > zebra 50), potem pliki (cherry 300 > banana 200)
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }
}
```

- [ ] **Step 2: Uruchom — ma NIE kompilować**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.files.FileSortTest"`
Expected: FAIL — `sortFileEntries` nie istnieje.

- [ ] **Step 3: Dodaj enumy i funkcję sortującą**

W `FilesProvider.kt`, nad `class FilesProvider` (po importach, ~linia 16), dodaj:

```kotlin
/** Klucz sortowania listy plików. Wartości zgodne z protokołem (sort_by). */
internal fun fileSortComparator(sortBy: String): Comparator<FileEntry> = when (sortBy) {
    "size" -> compareBy { it.size }
    "modified" -> compareBy { it.modified }
    "type" -> compareBy(
        { it.name.substringAfterLast('.', "").lowercase() },
        { it.name.lowercase() }
    )
    else -> compareBy { it.name.lowercase() }   // "name" / nieznane
}

/**
 * Czyste sortowanie listy wpisów. `foldersFirst` (gdy true) trzyma foldery na
 * górze niezależnie od kierunku; kierunek odwraca tylko porządek w obrębie grupy.
 */
internal fun sortFileEntries(
    entries: List<FileEntry>,
    sortBy: String,
    sortDir: String,
    foldersFirst: Boolean
): List<FileEntry> {
    var cmp = fileSortComparator(sortBy)
    if (sortDir == "desc") cmp = cmp.reversed()
    if (foldersFirst) {
        cmp = compareByDescending<FileEntry> { it.isDirectory }.then(cmp)
    }
    return entries.sortedWith(cmp)
}
```

- [ ] **Step 4: Uruchom — ma przejść**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.files.FileSortTest"`
Expected: PASS (4 testy).

- [ ] **Step 5: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt \
        android/Airbridge/app/src/test/java/com/airbridge/files/FileSortTest.kt
git commit -m "feat(android): pure sortFileEntries helper"
```

---

## Task 4: Android — `listDir` z sortowaniem + `searchDir`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt:30-54` (listDir) + nowa metoda `searchDir`

- [ ] **Step 1: Przebuduj `listDir` na nowe parametry sortowania**

Zamień metodę `listDir` (linie ~30-54) na:

```kotlin
    /** Listing katalogu (relPath="" = korzeń /sdcard). Zwraca (entries, totalCount). */
    fun listDir(
        relPath: String,
        page: Int,
        pageSize: Int,
        sortBy: String = "name",
        sortDir: String = "asc",
        foldersFirst: Boolean = true
    ): Pair<List<FileEntry>, Int> {
        val dir = File(root, relPath)
        val children = dir.listFiles() ?: return Pair(emptyList(), 0)

        val all = children.map { f -> toEntry(f, relPath) }
        val sorted = sortFileEntries(all, sortBy, sortDir, foldersFirst)
        val from = (page * pageSize).coerceAtMost(sorted.size)
        val to = (from + pageSize).coerceAtMost(sorted.size)
        return Pair(sorted.subList(from, to).toList(), sorted.size)
    }

    /** Mapuje plik na FileEntry z relatywną ścieżką liczoną względem `parentRel`. */
    private fun toEntry(f: File, parentRel: String): FileEntry {
        val isDir = f.isDirectory
        return FileEntry(
            name = f.name,
            relativePath = SafTreeStore.childPath(parentRel, f.name),
            isDirectory = isDir,
            size = if (isDir) 0 else f.length(),
            modified = f.lastModified(),
            mimeType = if (isDir) "inode/directory" else mimeFromName(f.name)
        )
    }
```

- [ ] **Step 2: Dodaj `searchDir` (rekurencyjny, od korzenia)**

Tuż po `listDir`/`toEntry` dodaj:

```kotlin
    /**
     * Globalny rekurencyjny search po nazwie od korzenia /sdcard. Dopasowanie
     * po podłańcuchu (case-insensitive). Early-stop po SEARCH_LIMIT trafieniach,
     * żeby walk całego drzewa nie wisiał. Zwraca (entries strony, totalCount trafień).
     */
    fun searchDir(
        query: String,
        page: Int,
        pageSize: Int,
        sortBy: String = "name",
        sortDir: String = "asc",
        foldersFirst: Boolean = true
    ): Pair<List<FileEntry>, Int> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return Pair(emptyList(), 0)
        val hits = ArrayList<FileEntry>()
        try {
            for (f in root.walkTopDown()) {
                if (f == root) continue
                if (f.name.lowercase().contains(needle)) {
                    val rel = f.relativeTo(root).path.replace(File.separatorChar, '/')
                    hits.add(toEntry(f, rel.substringBeforeLast('/', "")))
                    if (hits.size >= SEARCH_LIMIT) break
                }
            }
        } catch (e: Exception) {
            Log.e("FilesProvider", "searchDir walk failed for '$query'", e)
        }
        val sorted = sortFileEntries(hits, sortBy, sortDir, foldersFirst)
        val from = (page * pageSize).coerceAtMost(sorted.size)
        val to = (from + pageSize).coerceAtMost(sorted.size)
        return Pair(sorted.subList(from, to).toList(), sorted.size)
    }

    companion object {
        /** Górny limit trafień search, chroni przed pełnym walkiem /sdcard. */
        const val SEARCH_LIMIT = 500
    }
```

> Uwaga: `toEntry` liczy `relativePath` z przekazanego `parentRel`. W `searchDir` przekazujemy katalog nadrzędny trafienia (`rel` bez ostatniego segmentu), więc `SafTreeStore.childPath(parent, name)` odtworzy pełną ścieżkę względną identycznie jak w `listDir`.

- [ ] **Step 3: Zbuduj moduł (kompilacja)**

Run: `cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt
git commit -m "feat(android): sortable listDir + recursive searchDir"
```

---

## Task 5: Android — handler `FilesListRequest` (list vs search)

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt:845-874`

- [ ] **Step 1: Rozgałęź handler na list/search i przekaż parametry sortowania**

Zamień blok `is Message.FilesListRequest -> { ... }` (linie ~845-874) na:

```kotlin
            is Message.FilesListRequest -> {
                serviceScope.launch {
                    try {
                        if (!filesProvider.hasGrant()) {
                            webSocketClient.send(
                                Message.FilesListResponse(
                                    path = message.path,
                                    entries = emptyList(),
                                    totalCount = 0,
                                    page = message.page,
                                    needsPermission = true
                                )
                            )
                        } else {
                            val (entries, total) = if (message.query.isBlank()) {
                                filesProvider.listDir(
                                    message.path, message.page, message.pageSize,
                                    message.sortBy, message.sortDir, message.foldersFirst
                                )
                            } else {
                                filesProvider.searchDir(
                                    message.query, message.page, message.pageSize,
                                    message.sortBy, message.sortDir, message.foldersFirst
                                )
                            }
                            webSocketClient.send(
                                Message.FilesListResponse(
                                    path = message.path,
                                    entries = entries,
                                    totalCount = total,
                                    page = message.page,
                                    needsPermission = false
                                )
                            )
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "FilesListRequest failed", e)
                    }
                }
            }
```

> `path` w odpowiedzi zostaje równe `message.path` — macOS dopasowuje odpowiedź po `path == currentPath`. W trybie search macOS wyśle request z `path = currentPath`, więc dopasowanie dalej działa (patrz Task 6).

- [ ] **Step 2: Zbuduj**

Run: `cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt
git commit -m "feat(android): files handler routes list vs recursive search"
```

---

## Task 6: macOS — stan sortowania i wyszukiwania w `FilesBrowserService`

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift`

- [ ] **Step 1: Dodaj typy sortowania i stan**

Na górze pliku, po `import Protocol`, dodaj enumy:

```swift
enum FileSortKey: String, CaseIterable, Identifiable {
    case name, size, modified, type
    var id: String { rawValue }
}

enum FileViewMode: String {
    case list, grid
}
```

W klasie `FilesBrowserService`, po `private(set) var folderStats` (linia ~23), dodaj stan:

```swift
    private(set) var searchQuery: String = ""
    var sortBy: FileSortKey = .name {
        didSet { guard oldValue != sortBy else { return }; persistSort(); reload() }
    }
    var sortAscending: Bool = true {
        didSet { guard oldValue != sortAscending else { return }; persistSort(); reload() }
    }
    var foldersFirst: Bool = true {
        didSet { guard oldValue != foldersFirst else { return }; persistSort(); reload() }
    }
    /// Czy aktualnie pokazujemy wyniki wyszukiwania (globalne, rekurencyjne).
    var isSearching: Bool { !searchQuery.isEmpty }
```

> `view mode` trzymamy w widoku przez `@AppStorage` (Task 7) — nie wpływa na zapytania, więc nie musi być w service.

- [ ] **Step 2: Wczytaj i zapisuj sortowanie w UserDefaults**

W klasie dodaj (np. pod `configure`):

```swift
    func loadPersistedSort() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "files.sortBy"), let key = FileSortKey(rawValue: raw) {
            sortBy = key
        }
        if d.object(forKey: "files.sortAscending") != nil {
            sortAscending = d.bool(forKey: "files.sortAscending")
        }
        if d.object(forKey: "files.foldersFirst") != nil {
            foldersFirst = d.bool(forKey: "files.foldersFirst")
        }
    }

    private func persistSort() {
        let d = UserDefaults.standard
        d.set(sortBy.rawValue, forKey: "files.sortBy")
        d.set(sortAscending, forKey: "files.sortAscending")
        d.set(foldersFirst, forKey: "files.foldersFirst")
    }
```

> `didSet` w Step 1 wywoła `reload()` podczas `loadPersistedSort()`. To bezpieczne: `reload()` no-opuje gdy brak połączenia (`open` ma `guard connectionService.isConnected`). Wywołaj `loadPersistedSort()` raz z widoku w `.onAppear`.

- [ ] **Step 3: Przekaż sortowanie i query do `open(...)`**

Zamień metodę `open` (linie ~43-56) na wersję wysyłającą nowe pola:

```swift
    func open(path: String, page: Int = 0) {
        guard let connectionService, connectionService.isConnected else { return }
        isLoading = true
        if page == 0 {
            currentPath = path
            entries = []
            thumbnails = [:]
            requestedThumbnails = []
            folderStats = [:]
            requestedFolderStats = []
        }
        let message = Message.filesListRequest(
            path: path, page: page, pageSize: pageSize,
            sortBy: sortBy.rawValue,
            sortDir: sortAscending ? "asc" : "desc",
            foldersFirst: foldersFirst,
            query: searchQuery
        )
        Task { try? await connectionService.broadcast(message) }
    }
```

> `path` zostaje `currentPath` także podczas search — Android i tak ignoruje `path` gdy `query` niepuste, a macOS dopasowuje odpowiedź po `path == currentPath` (handler w `handleMessage` bez zmian).

- [ ] **Step 4: Dodaj debounce search**

W klasie dodaj pole i metodę:

```swift
    private var searchTask: Task<Void, Never>?

    /// Ustawia frazę z debounce ~300 ms; min. 2 znaki, inaczej czyści wyszukiwanie.
    func setSearchQuery(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        let effective = trimmed.count >= 2 ? trimmed : ""
        guard effective != searchQuery else { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.searchQuery = effective
            self.open(path: self.currentPath)
        }
    }
```

- [ ] **Step 5: W trybie search nie blokuj na folder-stats**

Zamień computed `displayedEntries` (linie ~100-107) na:

```swift
    var displayedEntries: [FileEntry] {
        // W trybie search wyniki to mix z różnych ścieżek — pokazujemy od razu,
        // bez czekania na rekurencyjne folder-stats.
        if isSearching { return entries }
        var result: [FileEntry] = []
        for e in entries {
            let ready = e.isDirectory ? folderStats[e.relativePath] != nil : true
            if ready { result.append(e) } else { break }
        }
        return result
    }
```

- [ ] **Step 6: Zbuduj**

Run: `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 7: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift
git commit -m "feat(macos): files browser sort+search state with debounce"
```

---

## Task 7: macOS — toolbar, siatka i wyniki search w `FilesBrowserView`

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift`

- [ ] **Step 1: Dodaj `@AppStorage` widoku i wczytanie sortowania**

W `struct FilesBrowserView`, po istniejących właściwościach (`let filesBrowserService`, `let connectionService`), dodaj:

```swift
    @AppStorage("files.viewMode") private var viewModeRaw: String = FileViewMode.list.rawValue
    @State private var searchText: String = ""

    private var viewMode: FileViewMode { FileViewMode(rawValue: viewModeRaw) ?? .list }
```

W `.onAppear` (linie ~21-25) dodaj na początku domknięcia:

```swift
            filesBrowserService.loadPersistedSort()
```

- [ ] **Step 2: Dodaj pasek narzędzi pod breadcrumbem**

W `body`, w gałęzi połączonej, wstaw `toolbarBar` między `breadcrumbBar` a `content`:

```swift
                VStack(spacing: 0) {
                    breadcrumbBar
                    toolbarBar
                    Divider()
                    content
                }
```

Dodaj computed `toolbarBar` (obok `breadcrumbBar`):

```swift
    private var toolbarBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.isPL ? "Szukaj wszędzie" : "Search everywhere", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, new in
                        filesBrowserService.setSearchQuery(new)
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; filesBrowserService.setSearchQuery("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            Spacer()

            sortMenu

            Picker("", selection: Binding(
                get: { viewMode },
                set: { viewModeRaw = $0.rawValue }
            )) {
                Image(systemName: "list.bullet").tag(FileViewMode.list)
                Image(systemName: "square.grid.2x2").tag(FileViewMode.grid)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.isPL ? "Sortuj wg" : "Sort by",
                   selection: Binding(get: { filesBrowserService.sortBy },
                                      set: { filesBrowserService.sortBy = $0 })) {
                Text(L10n.isPL ? "Nazwa" : "Name").tag(FileSortKey.name)
                Text(L10n.isPL ? "Rozmiar" : "Size").tag(FileSortKey.size)
                Text(L10n.isPL ? "Data modyfikacji" : "Date modified").tag(FileSortKey.modified)
                Text(L10n.isPL ? "Typ" : "Type").tag(FileSortKey.type)
            }
            Divider()
            Picker(L10n.isPL ? "Kierunek" : "Order",
                   selection: Binding(get: { filesBrowserService.sortAscending },
                                      set: { filesBrowserService.sortAscending = $0 })) {
                Text(L10n.isPL ? "Rosnąco" : "Ascending").tag(true)
                Text(L10n.isPL ? "Malejąco" : "Descending").tag(false)
            }
            Divider()
            Toggle(L10n.isPL ? "Foldery na początku" : "Folders first",
                   isOn: Binding(get: { filesBrowserService.foldersFirst },
                                 set: { filesBrowserService.foldersFirst = $0 }))
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
```

- [ ] **Step 3: Rozbij `content` na widok listy i siatki**

Zamniej computed `content` (linie ~72-96). Zachowaj gałęzie `needsPermission` i loadera, a `List` zamień na przełączanie list/grid:

```swift
    @ViewBuilder
    private var content: some View {
        if filesBrowserService.needsPermission {
            permissionEmptyState
        } else if filesBrowserService.displayedEntries.isEmpty
                    && (filesBrowserService.isLoading || filesBrowserService.isLoadingMoreRows) {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewMode == .grid {
            gridView
        } else {
            listView
        }
    }

    private var listView: some View {
        List {
            ForEach(filesBrowserService.displayedEntries) { entry in
                FileRow(
                    entry: entry,
                    thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                    stats: filesBrowserService.folderStats[entry.relativePath],
                    showPath: filesBrowserService.isSearching
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
            }
        }
        .listStyle(.inset)
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 16) {
                ForEach(filesBrowserService.displayedEntries) { entry in
                    FileGridCell(
                        entry: entry,
                        thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                        showPath: filesBrowserService.isSearching
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                }
            }
            .padding(16)
        }
        .animation(.default, value: filesBrowserService.displayedEntries.count)
    }
```

- [ ] **Step 4: Dodaj `showPath` do `FileRow`**

W `private struct FileRow`, dodaj właściwość i pokaż ścieżkę w trybie search. Zamień nagłówek struktury i `body`'s `Text(entry.name)` blok:

```swift
private struct FileRow: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    var stats: FolderStats? = nil
    var showPath: Bool = false
```

oraz w `VStack` zamień `Text(entry.name).lineLimit(1)` na:

```swift
                Text(showPath ? entry.relativePath : entry.name).lineLimit(1)
```

- [ ] **Step 5: Dodaj `FileGridCell`**

Na końcu pliku (po `FileRow`) dodaj nowy widok kafelka, reużywając matchera ikon z `FileRow`:

```swift
private struct FileGridCell: View {
    let entry: FileEntry
    let thumbnail: NSImage?
    var showPath: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: entry.isDirectory ? "folder.fill" : FileGridCell.symbol(for: entry.mimeType))
                        .font(.system(size: 34))
                        .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 96, height: 96)

            Text(showPath ? entry.relativePath : entry.name)
                .font(.caption).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: 104)
        }
    }

    static func symbol(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "music.note" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }
}
```

- [ ] **Step 6: Zbuduj**

Run: `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 7: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift
git commit -m "feat(macos): files toolbar (search, sort, list/grid) + grid view"
```

---

## Task 8: Weryfikacja end-to-end (ręczna)

**Files:** brak (build + uruchomienie).

- [ ] **Step 1: Pełne testy obu warstw protokołu**

Run: `cd android/Airbridge && ./gradlew :app:testDebugUnitTest`
Run: `cd macos/Airbridge && swift test`
Expected: wszystkie PASS.

- [ ] **Step 2: Build aplikacji**

Android: `cd android/Airbridge && ./gradlew :app:assembleDebug` → BUILD SUCCESSFUL.
macOS: uruchom przez `scripts/dev-install.sh` (zgodnie z preferencją — nie z DMG/bare binarki).

- [ ] **Step 3: Scenariusze ręczne (macOS połączony z telefonem)**

Sprawdź i potwierdź obserwacją:
- Sortowanie: zmiana klucza (nazwa/rozmiar/data/typ) i kierunku przestawia listę; „foldery na początku" działa; ustawienie utrzymuje się po restarcie apki (`@AppStorage`/UserDefaults).
- Widok: przełącznik Lista↔Siatka działa, miniaturki obrazów widoczne w obu; wybór utrzymuje się po restarcie.
- Search: wpisanie ≥2 znaków po ~300 ms pokazuje globalne wyniki z pełną ścieżką (`relativePath`); czyszczenie pola wraca do listingu bieżącego folderu; brak zacięć przy szukaniu z korzenia (limit 500).

- [ ] **Step 4: Commit (jeśli drobne poprawki po weryfikacji)**

```bash
git add -A && git commit -m "fix(files): post-verification tweaks"
```

---

## Self-Review

- **Spec coverage:** wyszukiwarka globalna (Task 1,2,4,5,6,7) ✓; sortowanie name/size/modified/type + kierunek + foldersFirst (Task 1,2,3,4,5,6,7) ✓; przełącznik lista/siatka (Task 7) ✓; backward-compat protokołu (Task 1 Step 4, Task 2 Step 6) ✓; debounce 300ms + min 2 znaki (Task 6 Step 4) ✓; limit search 500 (Task 4 Step 2) ✓; persist sort/widok (Task 6 Step 2, Task 7 Step 1) ✓; płaski rozmiar przy sortowaniu (Task 3 — `compareBy { it.size }`, folder=0) ✓; relativePath w wynikach search (Task 7 Step 4,5) ✓.
- **Type consistency:** `sortFileEntries(entries, sortBy, sortDir, foldersFirst)` spójne (Task 3↔4). Swift `FileSortKey`/`FileViewMode` zdefiniowane w Task 6 Step 1, użyte w Task 7. `setSearchQuery`, `loadPersistedSort`, `displayedEntries`, `isSearching` spójne między Task 6 a 7. `showPath` dodane do `FileRow` (Task 7 Step 4) i `FileGridCell` (Step 5).
- **Placeholders:** brak — każdy krok ma pełny kod i komendę z oczekiwanym wynikiem.
