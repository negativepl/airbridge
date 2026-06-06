# Files Upload-Dedup + Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upload pliku o istniejącej nazwie tworzy kopię `nazwa (1).ext` zamiast nadpisywać; dodać usuwanie plików i folderów (rekurencyjnie) z macOS z dialogiem potwierdzenia.

**Architecture:** Dedup to czysta funkcja `dedupedName` użyta w Android `createFile` (zero zmian protokołu). Delete to nowa para wiadomości `FileDeleteRequest`/`FileDeleteResponse` (Kotlin+Swift) → `FilesProvider.delete` → handler → macOS service `delete()` + `.contextMenu`/`.alert` w widoku. Po udanym delete macOS robi `reload()`.

**Tech Stack:** Kotlin (org.json, JUnit), Swift (Codable, XCTest, SwiftUI). Testy: Kotlin `./gradlew :app:testDebugUnitTest`, Swift `swift test --filter FilesMessageTests`.

---

## File Structure

- `android/.../protocol/Message.kt` — `FileDeleteRequest`/`FileDeleteResponse` (data class + toJson + fromJson).
- `android/.../files/FilesProvider.kt` — `dedupedName` (pure), `createFile` (dedup), `delete`.
- `android/.../service/AirbridgeService.kt` — handler `FileDeleteRequest`.
- `macos/.../Protocol/Message.swift` — `fileDeleteRequest`/`fileDeleteResponse` (case + TypeKey + encode + decode; CodingKeys `path`/`success`/`error` już istnieją).
- `macos/.../Services/FilesBrowserService.swift` — `delete`, `deleteError`, response handling.
- `macos/.../Views/FilesBrowserView.swift` — `.contextMenu` na wierszu/kafelku, `.alert` potwierdzenia + błędu.
- Testy: `FilesMessageTest.kt`, `FilesMessageTests.swift`, nowy `FileDedupTest.kt`.

**Kolejność:** protokół (Kotlin+Swift) → dedup (pure+createFile) → delete provider → handler → macOS service → macOS UI.

---

## Task 1: Protokół Kotlin — `FileDeleteRequest` / `FileDeleteResponse`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` — add 2 data classes near the other File* messages (after `FileDownloadRequest`, ~line 422), and 2 cases in `fromJson` (near `"file_download_request"`, ~line 778)
- Test: `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt`

- [ ] **Step 1: Add failing round-trip tests** — append to `FilesMessageTest.kt`:

```kotlin
    @Test fun fileDeleteRequestRoundTrip() {
        val msg = Message.FileDeleteRequest("DCIM/old.jpg")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteRequest
        assertEquals("DCIM/old.jpg", parsed.path)
    }

    @Test fun fileDeleteResponseSuccessRoundTrip() {
        val msg = Message.FileDeleteResponse("DCIM/old.jpg", true, null)
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteResponse
        assertEquals("DCIM/old.jpg", parsed.path)
        assertEquals(true, parsed.success)
        assertEquals(null, parsed.error)
    }

    @Test fun fileDeleteResponseErrorRoundTrip() {
        val msg = Message.FileDeleteResponse("DCIM/old.jpg", false, "delete_failed")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDeleteResponse
        assertEquals(false, parsed.success)
        assertEquals("delete_failed", parsed.error)
    }
```

- [ ] **Step 2: Run, verify FAIL (compile):** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: FAIL — `FileDeleteRequest`/`FileDeleteResponse` unresolved.

- [ ] **Step 3: Add the two data classes** in `Message.kt`, right after the `FileDownloadRequest` data class (the block ending ~line 422):

```kotlin
    data class FileDeleteRequest(
        val path: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_delete_request")
            put("path", path)
        }.toString()
    }

    data class FileDeleteResponse(
        val path: String,
        val success: Boolean,
        val error: String? = null
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_delete_response")
            put("path", path)
            put("success", success)
            if (error != null) put("error", error)
        }.toString()
    }
```

- [ ] **Step 4: Add two `fromJson` cases** right after the `"file_download_request"` case (~line 781):

```kotlin
                "file_delete_request" -> FileDeleteRequest(
                    path = obj.getString("path")
                )
                "file_delete_response" -> FileDeleteResponse(
                    path = obj.getString("path"),
                    success = obj.getBoolean("success"),
                    error = if (obj.has("error")) obj.getString("error") else null
                )
```

- [ ] **Step 5: Run, verify PASS:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: PASS (all).

- [ ] **Step 6: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt
git commit -m "feat(android-protocol): FileDelete request/response"
```

---

## Task 2: Protokół Swift — `fileDeleteRequest` / `fileDeleteResponse`

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift` — enum cases (after `fileDownloadRequest`, ~line 49), TypeKey (after `fileDownloadRequest`, ~line 306), encode (after `.fileDownloadRequest`, ~line 510), decode (after `.fileDownloadRequest`, ~line 764). CodingKeys `path`/`success`/`error` already exist.
- Test: `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift`

- [ ] **Step 1: Add failing tests** — append to `FilesMessageTests.swift`:

```swift
    func testFileDeleteRequestRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.fileDeleteRequest(path: "DCIM/old.jpg")),
                       .fileDeleteRequest(path: "DCIM/old.jpg"))
    }

    func testFileDeleteResponseSuccessRoundTrip() throws {
        let msg = Message.fileDeleteResponse(path: "DCIM/old.jpg", success: true, error: nil)
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFileDeleteResponseErrorRoundTrip() throws {
        let msg = Message.fileDeleteResponse(path: "DCIM/old.jpg", success: false, error: "delete_failed")
        XCTAssertEqual(try roundTrip(msg), msg)
    }
```

- [ ] **Step 2: Run, verify FAIL (compile):** `cd macos/Airbridge && swift test --filter FilesMessageTests`

- [ ] **Step 3: Add enum cases** after `case fileDownloadRequest(...)` (~line 49):

```swift
    case fileDeleteRequest(path: String)
    case fileDeleteResponse(path: String, success: Bool, error: String?)
```

- [ ] **Step 4: Add TypeKey entries** in `private enum TypeKey`, after `case fileDownloadRequest = "file_download_request"` (~line 306):

```swift
        case fileDeleteRequest        = "file_delete_request"
        case fileDeleteResponse       = "file_delete_response"
```

- [ ] **Step 5: Add encode cases** in `encode(to:)` after the `.fileDownloadRequest` case (~line 510):

```swift
        case .fileDeleteRequest(let path):
            try container.encode(TypeKey.fileDeleteRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)

        case .fileDeleteResponse(let path, let success, let error):
            try container.encode(TypeKey.fileDeleteResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(success, forKey: .success)
            try container.encodeIfPresent(error, forKey: .error)
```

- [ ] **Step 6: Add decode cases** in `init(from:)` after the `.fileDownloadRequest` case (~line 764):

```swift
        case .fileDeleteRequest:
            let path = try container.decode(String.self, forKey: .path)
            self = .fileDeleteRequest(path: path)

        case .fileDeleteResponse:
            let path = try container.decode(String.self, forKey: .path)
            let success = try container.decode(Bool.self, forKey: .success)
            let error = try container.decodeIfPresent(String.self, forKey: .error)
            self = .fileDeleteResponse(path: path, success: success, error: error)
```

- [ ] **Step 7: Run, verify PASS:** `cd macos/Airbridge && swift test --filter FilesMessageTests`
Expected: PASS (10 tests).

- [ ] **Step 8: Commit:**
```bash
git add macos/Airbridge/Sources/Protocol/Message.swift macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift
git commit -m "feat(macos-protocol): fileDelete request/response"
```

---

## Task 3: Android — czysta funkcja `dedupedName`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt` — add top-level `internal fun dedupedName` near `sortFileEntries` (above the class).
- Test: `android/Airbridge/app/src/test/java/com/airbridge/files/FileDedupTest.kt` (create)

- [ ] **Step 1: Create failing test** — `android/Airbridge/app/src/test/java/com/airbridge/files/FileDedupTest.kt`:

```kotlin
package com.airbridge.files

import org.junit.Assert.assertEquals
import org.junit.Test

class FileDedupTest {
    @Test fun noCollisionReturnsOriginal() {
        assertEquals("foto.jpg", dedupedName("foto.jpg") { false })
    }

    @Test fun oneCollisionAppendsOne() {
        val taken = setOf("foto.jpg")
        assertEquals("foto (1).jpg", dedupedName("foto.jpg") { it in taken })
    }

    @Test fun chainOfCollisions() {
        val taken = setOf("foto.jpg", "foto (1).jpg")
        assertEquals("foto (2).jpg", dedupedName("foto.jpg") { it in taken })
    }

    @Test fun noExtension() {
        val taken = setOf("nazwa")
        assertEquals("nazwa (1)", dedupedName("nazwa") { it in taken })
    }

    @Test fun multipleDotsNumberBeforeLastExtension() {
        val taken = setOf("a.tar.gz")
        assertEquals("a.tar (1).gz", dedupedName("a.tar.gz") { it in taken })
    }
}
```

- [ ] **Step 2: Run, verify FAIL:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.files.FileDedupTest"`
Expected: FAIL — `dedupedName` unresolved.

- [ ] **Step 3: Add the function** in `FilesProvider.kt`, above `class FilesProvider` (next to `sortFileEntries`):

```kotlin
/**
 * Zwraca nazwę pliku wolną wg predykatu `exists`. Jeśli `name` jest wolna, zwraca ją bez
 * zmian; inaczej dokleja `" (n)"` przed ostatnim rozszerzeniem: foto.jpg → foto (1).jpg,
 * a.tar.gz → a.tar (1).gz, nazwa → nazwa (1).
 */
internal fun dedupedName(name: String, exists: (String) -> Boolean): String {
    if (!exists(name)) return name
    val dot = name.lastIndexOf('.')
    val base = if (dot <= 0) name else name.substring(0, dot)
    val ext = if (dot <= 0) "" else name.substring(dot + 1)
    var i = 1
    while (true) {
        val candidate = if (ext.isEmpty()) "$base ($i)" else "$base ($i).$ext"
        if (!exists(candidate)) return candidate
        i++
    }
}
```

- [ ] **Step 4: Run, verify PASS:** `cd android/Airbridge && ./gradlew :app:testDebugUnitTest --tests "com.airbridge.files.FileDedupTest"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt android/Airbridge/app/src/test/java/com/airbridge/files/FileDedupTest.kt
git commit -m "feat(android): pure dedupedName helper"
```

---

## Task 4: Android — `createFile` dedup + `FilesProvider.delete`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt` — `createFile` (~line 190-200) and add `delete`.

- [ ] **Step 1: Make `createFile` pick a free name** — replace the `createFile` method body:

```kotlin
    /** Tworzy plik w katalogu relDir, wybierając wolną nazwę (bez nadpisywania istniejących),
     *  i zwraca (Uri, OutputStream) do zapisu (upload). Caller dostaje Uri, by móc skasować
     *  plik przy błędzie zapisu. */
    fun createFile(relDir: String, name: String, mimeType: String): Pair<Uri, OutputStream>? {
        return try {
            val dir = File(root, relDir)
            dir.mkdirs()
            val finalName = dedupedName(name) { File(dir, it).exists() }
            val f = File(dir, finalName)
            Pair(Uri.fromFile(f), FileOutputStream(f))
        } catch (e: Exception) {
            Log.e("FilesProvider", "createFile failed for $relDir/$name", e)
            null
        }
    }
```

- [ ] **Step 2: Add `delete`** right after `createFile`:

```kotlin
    /** Usuwa plik lub folder (rekurencyjnie). Zwraca true gdy usunięto.
     *  Pusty relPath (korzeń /sdcard) jest odrzucany dla bezpieczeństwa. */
    fun delete(relPath: String): Boolean {
        if (relPath.isBlank()) return false
        val target = File(root, relPath)
        if (!target.exists()) return false
        return try {
            if (target.isDirectory) target.deleteRecursively() else target.delete()
        } catch (e: Exception) {
            Log.e("FilesProvider", "delete failed for $relPath", e)
            false
        }
    }
```

- [ ] **Step 3: Compile + existing tests:**
```bash
cd android/Airbridge && ./gradlew :app:compileDebugKotlin && ./gradlew :app:testDebugUnitTest
```
Expected: BUILD SUCCESSFUL (FileDedupTest + others still pass).

- [ ] **Step 4: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt
git commit -m "feat(android): non-overwriting createFile + recursive delete"
```

---

## Task 5: Android — handler `FileDeleteRequest`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt` — add a `when` branch alongside the other `is Message.File*` handlers (e.g. after the `FilesListRequest` branch).

- [ ] **Step 1: Add the handler branch.** Find the `is Message.FilesListRequest ->` branch; after its closing `}` add:

```kotlin
            is Message.FileDeleteRequest -> {
                serviceScope.launch {
                    if (!filesProvider.hasGrant()) {
                        webSocketClient.send(
                            Message.FileDeleteResponse(message.path, false, "no_permission")
                        )
                    } else {
                        val ok = filesProvider.delete(message.path)
                        webSocketClient.send(
                            Message.FileDeleteResponse(message.path, ok, if (ok) null else "delete_failed")
                        )
                    }
                }
            }
```

- [ ] **Step 2: Compile:** `cd android/Airbridge && ./gradlew :app:compileDebugKotlin`
Expected: BUILD SUCCESSFUL. (If the `when(message)` is exhaustive over a sealed class and now warns/errors about the new subclasses being handled — they are handled here; `FileDeleteResponse` is outbound only and falls into the existing `else`/default branch, which is fine.)

- [ ] **Step 3: Commit:**
```bash
git add android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt
git commit -m "feat(android): handle FileDeleteRequest"
```

---

## Task 6: macOS — `FilesBrowserService.delete` + response handling

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift`

- [ ] **Step 1: Add `deleteError` state** — near the other `private(set) var` state (e.g. after `searchQuery`):

```swift
    /// Komunikat błędu ostatniego usuwania (nil = brak). UI pokazuje alert i czyści.
    var deleteError: String? = nil
```

- [ ] **Step 2: Add `delete(_:)`** — next to `download(_:)` in the `// MARK: - Transfer` area:

```swift
    func delete(_ entry: FileEntry) {
        guard let connectionService else { return }
        Task { try? await connectionService.broadcast(.fileDeleteRequest(path: entry.relativePath)) }
    }
```

- [ ] **Step 3: Handle the response** — in `handleMessage`, add a case alongside the existing `.filesListResponse` / `.fileThumbnailResponse` / `.folderStatsResponse` cases (before `default`):

```swift
        case .fileDeleteResponse(_, let success, let error):
            if success {
                reload()
            } else {
                deleteError = error ?? "delete_failed"
            }
```

- [ ] **Step 4: Build:** `cd macos/Airbridge && swift build`
Expected: Build complete.

- [ ] **Step 5: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift
git commit -m "feat(macos): files delete request + response handling"
```

---

## Task 7: macOS — context menu + alert potwierdzenia

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift`

- [ ] **Step 1: Add deletion state** — after the existing `@State private var searchText` (~line 10):

```swift
    @State private var entryPendingDeletion: FileEntry?
```

- [ ] **Step 2: Add context menu to the list rows** — in `listView`, on the `FileRow` row, add `.contextMenu` after the existing `.onTapGesture`:

```swift
                FileRow(
                    entry: entry,
                    thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                    stats: filesBrowserService.folderStats[entry.relativePath],
                    showPath: filesBrowserService.isSearching
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                .contextMenu {
                    Button(role: .destructive) { entryPendingDeletion = entry } label: {
                        Label(L10n.isPL ? "Usuń" : "Delete", systemImage: "trash")
                    }
                }
```

- [ ] **Step 3: Add context menu to the grid cells** — in `gridView`, on the `FileGridCell`, add the same `.contextMenu` after its `.onTapGesture`:

```swift
                    FileGridCell(
                        entry: entry,
                        thumbnail: filesBrowserService.thumbnails[entry.relativePath],
                        showPath: filesBrowserService.isSearching
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                    .contextMenu {
                        Button(role: .destructive) { entryPendingDeletion = entry } label: {
                            Label(L10n.isPL ? "Usuń" : "Delete", systemImage: "trash")
                        }
                    }
```

- [ ] **Step 4: Add the confirmation + error alerts** — in `body`, add two `.alert` modifiers after the existing `.onDrop(...)` (still on the outer `Group`):

```swift
        .alert(
            entryPendingDeletion.map {
                L10n.isPL ? "Usunąć „\($0.name)”?" : "Delete \"\($0.name)\"?"
            } ?? "",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            presenting: entryPendingDeletion
        ) { entry in
            Button(L10n.isPL ? "Usuń" : "Delete", role: .destructive) {
                filesBrowserService.delete(entry)
                entryPendingDeletion = nil
            }
            Button(L10n.isPL ? "Anuluj" : "Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: { _ in
            Text(L10n.isPL ? "Tej operacji nie można cofnąć." : "This cannot be undone.")
        }
        .alert(
            L10n.isPL ? "Nie udało się usunąć" : "Delete failed",
            isPresented: Binding(
                get: { filesBrowserService.deleteError != nil },
                set: { if !$0 { filesBrowserService.deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { filesBrowserService.deleteError = nil }
        }
```

Note: `deleteError` is a settable `var` on the `@Observable` service, so the `Binding` set-closure can clear it directly.

- [ ] **Step 5: Build:** `cd macos/Airbridge && swift build`
Expected: Build complete. (Ignore SourceKit "No such module Protocol" false positives if `swift build` succeeds.)

- [ ] **Step 6: Commit:**
```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift
git commit -m "feat(macos): delete context menu + confirmation alert"
```

---

## Task 8: Weryfikacja (ręczna e2e)

- [ ] **Step 1: Full tests both layers:**
```bash
cd android/Airbridge && ./gradlew :app:testDebugUnitTest
cd ../../macos/Airbridge && swift test --filter FilesMessageTests
```
Expected: all PASS (Mirror integration failures are pre-existing and unrelated).

- [ ] **Step 2: Build apps:** Android `./gradlew :app:assembleDebug`; macOS via `scripts/dev-install.sh`.

- [ ] **Step 3: Manual scenarios (phone connected):**
  - **Dedup:** wgraj (drag&drop) plik o nazwie istniejącej w bieżącym folderze → na telefonie powstaje `nazwa (1).ext`, oryginał nietknięty; wgraj ponownie → `nazwa (2).ext`.
  - **Delete plik:** prawy klik na pliku → „Usuń" → potwierdź → plik znika z listy (reload), zniknął też na telefonie.
  - **Delete folder:** prawy klik na folderze → „Usuń" → potwierdź → folder z zawartością znika.
  - **Anuluj:** otwórz dialog, „Anuluj" → nic nie usunięte.
  - **Grid:** to samo menu kontekstowe działa w widoku siatki.
  - **Błąd:** (jeśli uda się wywołać) alert „Nie udało się usunąć".

- [ ] **Step 4: Commit ewentualnych poprawek po weryfikacji.**

---

## Self-Review

- **Spec coverage:** dedup `nazwa (1).ext` (Task 3,4) ✓; numer przed ostatnim rozszerzeniem `a.tar.gz`→`a.tar (1).gz` (Task 3 test + funkcja) ✓; brak zmian protokołu dla uploadu ✓; `FileDeleteRequest`/`FileDeleteResponse` z opcjonalnym `error` Kotlin+Swift (Task 1,2) ✓; `delete` rekurencyjny + guard na korzeń (Task 4) ✓; handler z `hasGrant` (Task 5) ✓; macOS `delete` + reload przy success + `deleteError` (Task 6) ✓; context menu lista+siatka + alert potwierdzenia + alert błędu (Task 7) ✓.
- **Type consistency:** `dedupedName(name, exists)` (Task 3↔4). `FileDeleteRequest(path)`, `FileDeleteResponse(path, success, error?)` spójne Kotlin↔Swift↔handler↔service. `entryPendingDeletion: FileEntry?`, `deleteError: String?`, `delete(_ entry)` spójne Task 6↔7.
- **Placeholders:** brak — każdy krok ma pełny kod i komendę z oczekiwanym wynikiem.
