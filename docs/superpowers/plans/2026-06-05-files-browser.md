# Files Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dodać do aplikacji macOS przeglądarkę plików telefonu (Finder-like) z dwukierunkowym transferem: nawigacja po folderach, podgląd, ściąganie na Maca i wgrywanie z Maca do wybranego folderu na telefonie.

**Architecture:** Uogólnienie wzorca Galerii — nowe typy wiadomości WebSocket JSON, `FilesProvider` po stronie Androida (Storage Access Framework / `DocumentFile`), `FilesBrowserService` + `FilesBrowserView` po stronie Maca. Transfer góra/dół reużywa istniejącego `FileTransferService` (binary chunks Android→Mac, HTTP pull Mac→Android). Dostęp do plików przez jednorazowy grant SAF na drzewo — zero nowych uprawnień w manifeście.

**Tech Stack:** Swift (Codable enum protokół, `@Observable @MainActor` services, SwiftUI), Kotlin (sealed `Message` + `org.json`, `DocumentsContract`/`DocumentFile`, ContentResolver), WebSocket + HTTP.

**Spec:** `docs/superpowers/specs/2026-06-05-files-browser-design.md`

---

## File Structure

**Tworzone:**
- `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt` — odczyt drzewa SAF, listing, thumbnaile, streamy I/O
- `android/Airbridge/app/src/main/java/com/airbridge/files/SafTreeStore.kt` — persystencja tree URI + pure helper rozbicia ścieżki (testowalny)
- `android/Airbridge/app/src/test/java/com/airbridge/files/SafTreeStoreTest.kt` — unit test path-split
- `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt` — round-trip protokołu (Kotlin)
- `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift` — service Maca
- `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift` — ekran Finder-like
- `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift` — round-trip protokołu (Swift)

**Modyfikowane:**
- `macos/Airbridge/Sources/Protocol/Message.swift` — nowe case'y + `FileEntry` + `destinationDir` w `fileTransferOffer`
- `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt` — analogicznie
- `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift` — rejestracja + routing
- `macos/Airbridge/Sources/AirbridgeApp/Services/FileTransferService.swift` — `destinationDir` w ofercie + download zapisany do `~/Downloads`
- `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift` — utworzenie + wiring `FilesBrowserService`
- `macos/Airbridge/Sources/AirbridgeApp/Navigation/NavigationItem.swift` — `case files`
- `macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift` — `Tab(.files)` + przekazanie service
- `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt` — handler nowych requestów + `destinationDir` przy uploadzie
- Wizard uprawnień Android (plik do zlokalizowania w Task 4) — przycisk + launcher SAF

---

## WAŻNE: pliki do przeczytania przed startem

Niektóre obszary (transfer Android→Mac jako binary chunks, odbiór oferty + GET po stronie Androida, wizard uprawnień) nie są w pełni zacytowane w tym planie. **Przed Taskami 4, 5 i 8 przeczytaj odpowiednie istniejące funkcje** wskazane w tych taskach i naśladuj ich wzorzec — nie wymyślaj API.

---

## Task 1: Protokół macOS — `FileEntry` + wiadomości plików (Swift)

**Files:**
- Modify: `macos/Airbridge/Sources/Protocol/Message.swift`
- Test: `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift`

Wzorzec 1:1 jak istniejące `gallery*` case'y (Message.swift:38-44, 161-167, 290-322, 471-503).

- [ ] **Step 1: Napisz failing test round-trip**

Utwórz `macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift`:

```swift
import XCTest
@testable import Protocol

final class FilesMessageTests: XCTestCase {
    private func roundTrip(_ message: Message) throws -> Message {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(Message.self, from: data)
    }

    func testFilesListRequestRoundTrip() throws {
        let msg = Message.filesListRequest(path: "Download", page: 0, pageSize: 200)
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFilesListResponseRoundTrip() throws {
        let entry = FileEntry(name: "a.pdf", relativePath: "Download/a.pdf", isDirectory: false,
                              size: 1234, modified: 1_700_000_000_000, mimeType: "application/pdf")
        let msg = Message.filesListResponse(path: "Download", entries: [entry],
                                            totalCount: 1, page: 0, needsPermission: false)
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFileThumbnailRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.fileThumbnailRequest(path: "DCIM/x.jpg")),
                       .fileThumbnailRequest(path: "DCIM/x.jpg"))
        XCTAssertEqual(try roundTrip(.fileThumbnailResponse(path: "DCIM/x.jpg", data: "QQ==")),
                       .fileThumbnailResponse(path: "DCIM/x.jpg", data: "QQ=="))
    }

    func testFileDownloadRequestRoundTrip() throws {
        let msg = Message.fileDownloadRequest(transferId: "T1", path: "Download/a.pdf")
        XCTAssertEqual(try roundTrip(msg), msg)
    }

    func testFileTransferOfferWithDestinationRoundTrip() throws {
        let msg = Message.fileTransferOffer(transferId: "T1", filename: "a.pdf",
                                            mimeType: "application/pdf", fileSize: 10, destinationDir: "Download")
        XCTAssertEqual(try roundTrip(msg), msg)
    }
}
```

- [ ] **Step 2: Uruchom test — ma się nie skompilować/failować**

Run: `cd macos/Airbridge && swift test --filter FilesMessageTests`
Expected: FAIL — `FileEntry` i nowe case'y nie istnieją.

- [ ] **Step 3: Dodaj `FileEntry` struct**

W `Message.swift` po `GalleryPhotoMeta` (linia ~85) dodaj:

```swift
// MARK: - FileEntry

public struct FileEntry: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let relativePath: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Int64   // epoch millis
    public let mimeType: String

    public var id: String { relativePath }

    private enum CodingKeys: String, CodingKey {
        case name, size, modified
        case relativePath = "relative_path"
        case isDirectory  = "is_directory"
        case mimeType     = "mime_type"
    }

    public init(name: String, relativePath: String, isDirectory: Bool, size: Int64, modified: Int64, mimeType: String) {
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.mimeType = mimeType
    }
}
```

- [ ] **Step 4: Dodaj case'y do enum `Message`**

W `enum Message` po `.galleryDownloadRequest` (linia 44) dodaj:

```swift
    case filesListRequest(path: String, page: Int, pageSize: Int)
    case filesListResponse(path: String, entries: [FileEntry], totalCount: Int, page: Int, needsPermission: Bool)
    case fileThumbnailRequest(path: String)
    case fileThumbnailResponse(path: String, data: String)
    case fileDownloadRequest(transferId: String, path: String)
```

Zmień sygnaturę `fileTransferOffer` (linia 51) na:

```swift
    case fileTransferOffer(transferId: String, filename: String, mimeType: String, fileSize: Int64, destinationDir: String?)
```

- [ ] **Step 5: Dodaj `TypeKey` rawValues**

W `enum TypeKey` po `galleryDownloadRequest` (linia 167) dodaj:

```swift
        case filesListRequest         = "files_list_request"
        case filesListResponse        = "files_list_response"
        case fileThumbnailRequest     = "file_thumbnail_request"
        case fileThumbnailResponse    = "file_thumbnail_response"
        case fileDownloadRequest      = "file_download_request"
```

- [ ] **Step 6: Dodaj `CodingKeys`**

W `enum CodingKeys` (po linii 215, `case token`) dodaj brakujące klucze:

```swift
        case path
        case entries
        case isDirectory   = "is_directory"
        case needsPermission = "needs_permission"
        case destinationDir  = "destination_dir"
```

(Klucze `page`, `pageSize`, `totalCount`, `data`, `transferId` już istnieją — reużyj.)

- [ ] **Step 7: Dodaj gałęzie `encode`**

W `func encode` po bloku `.galleryDownloadRequest` (linia 322) dodaj:

```swift
        case .filesListRequest(let path, let page, let pageSize):
            try container.encode(TypeKey.filesListRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(page, forKey: .page)
            try container.encode(pageSize, forKey: .pageSize)

        case .filesListResponse(let path, let entries, let totalCount, let page, let needsPermission):
            try container.encode(TypeKey.filesListResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(entries, forKey: .entries)
            try container.encode(totalCount, forKey: .totalCount)
            try container.encode(page, forKey: .page)
            try container.encode(needsPermission, forKey: .needsPermission)

        case .fileThumbnailRequest(let path):
            try container.encode(TypeKey.fileThumbnailRequest.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)

        case .fileThumbnailResponse(let path, let data):
            try container.encode(TypeKey.fileThumbnailResponse.rawValue, forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encode(data, forKey: .data)

        case .fileDownloadRequest(let transferId, let path):
            try container.encode(TypeKey.fileDownloadRequest.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(path, forKey: .path)
```

Zmień blok `.fileTransferOffer` (linia 358) na:

```swift
        case .fileTransferOffer(let transferId, let filename, let mimeType, let fileSize, let destinationDir):
            try container.encode(TypeKey.fileTransferOffer.rawValue, forKey: .type)
            try container.encode(transferId, forKey: .transferId)
            try container.encode(filename, forKey: .filename)
            try container.encode(mimeType, forKey: .mimeType)
            try container.encode(fileSize, forKey: .fileSize)
            try container.encodeIfPresent(destinationDir, forKey: .destinationDir)
```

- [ ] **Step 8: Dodaj gałęzie `decode`**

W `init(from:)` po bloku `.galleryDownloadRequest` (linia 503) dodaj:

```swift
        case .filesListRequest:
            let path = try container.decode(String.self, forKey: .path)
            let page = try container.decode(Int.self, forKey: .page)
            let pageSize = try container.decode(Int.self, forKey: .pageSize)
            self = .filesListRequest(path: path, page: page, pageSize: pageSize)

        case .filesListResponse:
            let path = try container.decode(String.self, forKey: .path)
            let entries = try container.decode([FileEntry].self, forKey: .entries)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let page = try container.decode(Int.self, forKey: .page)
            let needsPermission = try container.decode(Bool.self, forKey: .needsPermission)
            self = .filesListResponse(path: path, entries: entries, totalCount: totalCount, page: page, needsPermission: needsPermission)

        case .fileThumbnailRequest:
            let path = try container.decode(String.self, forKey: .path)
            self = .fileThumbnailRequest(path: path)

        case .fileThumbnailResponse:
            let path = try container.decode(String.self, forKey: .path)
            let data = try container.decode(String.self, forKey: .data)
            self = .fileThumbnailResponse(path: path, data: data)

        case .fileDownloadRequest:
            let transferId = try container.decode(String.self, forKey: .transferId)
            let path = try container.decode(String.self, forKey: .path)
            self = .fileDownloadRequest(transferId: transferId, path: path)
```

Zmień blok `.fileTransferOffer` (linia 539) na:

```swift
        case .fileTransferOffer:
            let transferId = try container.decode(String.self, forKey: .transferId)
            let filename = try container.decode(String.self, forKey: .filename)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            let fileSize = try container.decode(Int64.self, forKey: .fileSize)
            let destinationDir = try container.decodeIfPresent(String.self, forKey: .destinationDir)
            self = .fileTransferOffer(transferId: transferId, filename: filename, mimeType: mimeType, fileSize: fileSize, destinationDir: destinationDir)
```

- [ ] **Step 9: Napraw istniejące call-site `fileTransferOffer`**

W `FileTransferService.swift:235` dodaj `destinationDir: nil` do konstrukcji oferty (zostanie nadpisane w Task 8). Tymczasowo:

```swift
            let offer = Message.fileTransferOffer(transferId: transferId, filename: filename, mimeType: mime, fileSize: fileSize, destinationDir: nil)
```

- [ ] **Step 10: Uruchom test — ma przejść**

Run: `cd macos/Airbridge && swift test --filter FilesMessageTests`
Expected: PASS (5 testów).

- [ ] **Step 11: Commit**

```bash
git add macos/Airbridge/Sources/Protocol/Message.swift macos/Airbridge/Tests/ProtocolTests/FilesMessageTests.swift macos/Airbridge/Sources/AirbridgeApp/Services/FileTransferService.swift
git commit -m "feat(files): add files browser protocol messages (macOS)"
```

---

## Task 2: Protokół Android — `FileEntry` + wiadomości plików (Kotlin)

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt`

Pola JSON MUSZĄ być identyczne ze stroną Swift (snake_case: `relative_path`, `is_directory`, `mime_type`, `needs_permission`, `destination_dir`, `page_size`, `total_count`).

- [ ] **Step 1: Napisz failing test**

Utwórz `android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt`:

```kotlin
package com.airbridge.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class FilesMessageTest {
    @Test fun filesListRequestRoundTrip() {
        val msg = Message.FilesListRequest(path = "Download", page = 0, pageSize = 200)
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListRequest
        assertEquals("Download", parsed.path)
        assertEquals(200, parsed.pageSize)
    }

    @Test fun filesListResponseRoundTrip() {
        val entry = FileEntry("a.pdf", "Download/a.pdf", false, 1234, 1_700_000_000_000, "application/pdf")
        val msg = Message.FilesListResponse("Download", listOf(entry), 1, 0, false)
        val parsed = Message.fromJson(msg.toJson()) as Message.FilesListResponse
        assertEquals(1, parsed.entries.size)
        assertEquals("Download/a.pdf", parsed.entries[0].relativePath)
        assertFalse(parsed.needsPermission)
    }

    @Test fun fileDownloadRequestRoundTrip() {
        val msg = Message.FileDownloadRequest("T1", "Download/a.pdf")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileDownloadRequest
        assertEquals("T1", parsed.transferId)
        assertEquals("Download/a.pdf", parsed.path)
    }

    @Test fun fileTransferOfferWithDestination() {
        val msg = Message.FileTransferOffer("T1", "a.pdf", "application/pdf", 10, "Download")
        val parsed = Message.fromJson(msg.toJson()) as Message.FileTransferOffer
        assertEquals("Download", parsed.destinationDir)
    }
}
```

- [ ] **Step 2: Uruchom test — ma failować**

Run: `cd android/Airbridge && ./gradlew testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: FAIL — `FileEntry` i nowe klasy nie istnieją.

- [ ] **Step 3: Dodaj `FileEntry` data class**

W `Message.kt` po `data class PhotoMeta` (linia 14) dodaj:

```kotlin
data class FileEntry(
    val name: String,
    val relativePath: String,
    val isDirectory: Boolean,
    val size: Long,
    val modified: Long,
    val mimeType: String
)
```

- [ ] **Step 4: Dodaj nowe podklasy `Message`**

Po `GalleryDownloadRequest` (linia 308) dodaj:

```kotlin
    data class FilesListRequest(
        val path: String,
        val page: Int,
        val pageSize: Int
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "files_list_request")
            put("path", path)
            put("page", page)
            put("page_size", pageSize)
        }.toString()
    }

    data class FilesListResponse(
        val path: String,
        val entries: List<FileEntry>,
        val totalCount: Int,
        val page: Int,
        val needsPermission: Boolean
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "files_list_response")
            put("path", path)
            put("total_count", totalCount)
            put("page", page)
            put("needs_permission", needsPermission)
            put("entries", JSONArray().apply {
                entries.forEach { e ->
                    put(JSONObject().apply {
                        put("name", e.name)
                        put("relative_path", e.relativePath)
                        put("is_directory", e.isDirectory)
                        put("size", e.size)
                        put("modified", e.modified)
                        put("mime_type", e.mimeType)
                    })
                }
            })
        }.toString()
    }

    data class FileThumbnailRequest(
        val path: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_thumbnail_request")
            put("path", path)
        }.toString()
    }

    data class FileThumbnailResponse(
        val path: String,
        val data: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_thumbnail_response")
            put("path", path)
            put("data", data)
        }.toString()
    }

    data class FileDownloadRequest(
        val transferId: String,
        val path: String
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_download_request")
            put("transfer_id", transferId)
            put("path", path)
        }.toString()
    }
```

- [ ] **Step 5: Dodaj `destinationDir` do `FileTransferOffer`**

Zmień `data class FileTransferOffer` (linia 122-135) na:

```kotlin
    data class FileTransferOffer(
        val transferId: String,
        val filename: String,
        val mimeType: String,
        val fileSize: Long,
        val destinationDir: String? = null
    ) : Message() {
        override fun toJson(): String = JSONObject().apply {
            put("type", "file_transfer_offer")
            put("transfer_id", transferId)
            put("filename", filename)
            put("mime_type", mimeType)
            put("file_size", fileSize)
            if (destinationDir != null) put("destination_dir", destinationDir)
        }.toString()
    }
```

- [ ] **Step 6: Dodaj parsowanie w `fromJson`**

W `when (type)` po `"gallery_download_request"` (linia 537) dodaj:

```kotlin
                "files_list_request" -> FilesListRequest(
                    path = obj.getString("path"),
                    page = obj.optInt("page", 0),
                    pageSize = obj.optInt("page_size", 200)
                )
                "files_list_response" -> {
                    val arr = obj.getJSONArray("entries")
                    val entries = (0 until arr.length()).map { i ->
                        val e = arr.getJSONObject(i)
                        FileEntry(
                            name = e.getString("name"),
                            relativePath = e.getString("relative_path"),
                            isDirectory = e.getBoolean("is_directory"),
                            size = e.getLong("size"),
                            modified = e.getLong("modified"),
                            mimeType = e.getString("mime_type")
                        )
                    }
                    FilesListResponse(
                        path = obj.getString("path"),
                        entries = entries,
                        totalCount = obj.getInt("total_count"),
                        page = obj.getInt("page"),
                        needsPermission = obj.getBoolean("needs_permission")
                    )
                }
                "file_thumbnail_request" -> FileThumbnailRequest(path = obj.getString("path"))
                "file_thumbnail_response" -> FileThumbnailResponse(
                    path = obj.getString("path"),
                    data = obj.getString("data")
                )
                "file_download_request" -> FileDownloadRequest(
                    transferId = obj.getString("transfer_id"),
                    path = obj.getString("path")
                )
```

Zmień gałąź `"file_transfer_offer"` (linia 463) na:

```kotlin
                "file_transfer_offer" -> FileTransferOffer(
                    transferId = obj.getString("transfer_id"),
                    filename = obj.getString("filename"),
                    mimeType = obj.getString("mime_type"),
                    fileSize = obj.getLong("file_size"),
                    destinationDir = if (obj.has("destination_dir")) obj.getString("destination_dir") else null
                )
```

- [ ] **Step 7: Uruchom test — ma przejść**

Run: `cd android/Airbridge && ./gradlew testDebugUnitTest --tests "com.airbridge.protocol.FilesMessageTest"`
Expected: PASS (4 testy).

- [ ] **Step 8: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/protocol/Message.kt android/Airbridge/app/src/test/java/com/airbridge/protocol/FilesMessageTest.kt
git commit -m "feat(files): add files browser protocol messages (Android)"
```

---

## Task 3: Android — `SafTreeStore` (persystencja tree URI + path helper)

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/files/SafTreeStore.kt`
- Test: `android/Airbridge/app/src/test/java/com/airbridge/files/SafTreeStoreTest.kt`

Wydzielamy czystą, testowalną logikę rozbicia ścieżki względnej na segmenty (resztę SAF testujemy manualnie na urządzeniu — `DocumentsContract` nie działa w JVM unit test).

- [ ] **Step 1: Napisz failing test**

Utwórz `android/Airbridge/app/src/test/java/com/airbridge/files/SafTreeStoreTest.kt`:

```kotlin
package com.airbridge.files

import org.junit.Assert.assertEquals
import org.junit.Test

class SafTreeStoreTest {
    @Test fun emptyPathHasNoSegments() {
        assertEquals(emptyList<String>(), SafTreeStore.pathSegments(""))
    }

    @Test fun singleSegment() {
        assertEquals(listOf("Download"), SafTreeStore.pathSegments("Download"))
    }

    @Test fun nestedSegmentsTrimSlashes() {
        assertEquals(listOf("Download", "Sub"), SafTreeStore.pathSegments("/Download/Sub/"))
    }

    @Test fun collapsesEmptySegments() {
        assertEquals(listOf("A", "B"), SafTreeStore.pathSegments("A//B"))
    }

    @Test fun childPathJoins() {
        assertEquals("Download/a.pdf", SafTreeStore.childPath("Download", "a.pdf"))
        assertEquals("a.pdf", SafTreeStore.childPath("", "a.pdf"))
    }
}
```

- [ ] **Step 2: Uruchom test — ma failować**

Run: `cd android/Airbridge && ./gradlew testDebugUnitTest --tests "com.airbridge.files.SafTreeStoreTest"`
Expected: FAIL — `SafTreeStore` nie istnieje.

- [ ] **Step 3: Napisz `SafTreeStore`**

Utwórz `android/Airbridge/app/src/main/java/com/airbridge/files/SafTreeStore.kt`:

```kotlin
package com.airbridge.files

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri

/**
 * Przechowuje grant SAF (tree URI) i dostarcza czyste helpery na ścieżki względne.
 * Ścieżka względna używa "/" jako separatora, korzeń = "".
 */
class SafTreeStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveTreeUri(uri: Uri) {
        prefs.edit().putString(KEY_TREE_URI, uri.toString()).apply()
    }

    fun treeUri(): Uri? = prefs.getString(KEY_TREE_URI, null)?.let(Uri::parse)

    fun hasGrant(): Boolean = treeUri() != null

    companion object {
        private const val PREFS = "saf_tree"
        private const val KEY_TREE_URI = "tree_uri"

        /** Rozbija ścieżkę względną na segmenty, pomijając puste. */
        fun pathSegments(path: String): List<String> =
            path.split("/").filter { it.isNotEmpty() }

        /** Łączy katalog względny z nazwą dziecka. */
        fun childPath(dir: String, name: String): String =
            if (dir.isEmpty()) name else "$dir/$name"
    }
}
```

- [ ] **Step 4: Uruchom test — ma przejść**

Run: `cd android/Airbridge && ./gradlew testDebugUnitTest --tests "com.airbridge.files.SafTreeStoreTest"`
Expected: PASS (5 testów).

- [ ] **Step 5: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/SafTreeStore.kt android/Airbridge/app/src/test/java/com/airbridge/files/SafTreeStoreTest.kt
git commit -m "feat(files): SafTreeStore for SAF grant persistence + path helpers"
```

---

## Task 4: Android — `FilesProvider` (listing + thumbnaile + I/O przez DocumentFile)

**Files:**
- Create: `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt`

**PRZECZYTAJ NAJPIERW:** `GalleryProvider.kt` (wzorzec `decodeScaled`/base64 thumbnaili — przeniesiemy do plików obrazowych). Brak unit-testu (SAF wymaga urządzenia) — weryfikacja manualna w Task 9.

Mechanika SAF: z `treeUri` budujemy document URI korzenia przez `DocumentsContract.getTreeDocumentId` + `buildDocumentUriUsingTree`. Listing dziecka: `buildChildDocumentsUriUsingTree(treeUri, parentDocId)` i query kolumn `DOCUMENT_ID/DISPLAY_NAME/MIME_TYPE/SIZE/LAST_MODIFIED`. Nawigację po `relativePath` realizujemy przez kolejne resolucje `displayName → documentId` (cache w `docIdCache: MutableMap<String, String>`).

- [ ] **Step 1: Napisz `FilesProvider`**

Utwórz `android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt`:

```kotlin
package com.airbridge.files

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import android.util.Log
import com.airbridge.protocol.FileEntry
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream

class FilesProvider(
    private val contentResolver: ContentResolver,
    private val store: SafTreeStore
) {
    // relativePath -> documentId (cache nawigacji)
    private val docIdCache = mutableMapOf<String, String>()

    fun hasGrant(): Boolean = store.hasGrant()

    /** Listing katalogu (relPath="" = korzeń grantu). Zwraca (entries, totalCount). */
    fun listDir(relPath: String, page: Int, pageSize: Int): Pair<List<FileEntry>, Int> {
        val treeUri = store.treeUri() ?: return Pair(emptyList(), 0)
        val docId = resolveDocId(treeUri, relPath) ?: return Pair(emptyList(), 0)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)

        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )

        val all = mutableListOf<FileEntry>()
        contentResolver.query(childrenUri, projection, null, null, null)?.use { c ->
            val nameCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (c.moveToNext()) {
                val name = c.getString(nameCol) ?: continue
                val mime = c.getString(mimeCol) ?: "application/octet-stream"
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                all.add(
                    FileEntry(
                        name = name,
                        relativePath = SafTreeStore.childPath(relPath, name),
                        isDirectory = isDir,
                        size = if (isDir) 0 else c.getLong(sizeCol),
                        modified = c.getLong(modCol),
                        mimeType = if (isDir) "inode/directory" else mime
                    )
                )
            }
        }

        // Foldery najpierw, potem alfabetycznie (case-insensitive)
        val sorted = all.sortedWith(
            compareByDescending<FileEntry> { it.isDirectory }
                .thenBy { it.name.lowercase() }
        )
        val from = (page * pageSize).coerceAtMost(sorted.size)
        val to = (from + pageSize).coerceAtMost(sorted.size)
        return Pair(sorted.subList(from, to).toList(), sorted.size)
    }

    /** Thumbnail dla obrazów (skala 400px, JPEG q75, base64). null dla nie-obrazów. */
    fun getThumbnail(relPath: String): String? {
        val treeUri = store.treeUri() ?: return null
        val docId = resolveDocId(treeUri, relPath) ?: return null
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
            var sample = 1
            while (opts.outWidth / sample > 800 || opts.outHeight / sample > 800) sample *= 2
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, decodeOpts)
            } ?: return null
            val scale = 400f / maxOf(bitmap.width, bitmap.height).coerceAtLeast(1)
            val scaled = if (scale < 1f)
                Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
            else bitmap
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.JPEG, 75, out)
            if (scaled !== bitmap) scaled.recycle()
            bitmap.recycle()
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("FilesProvider", "getThumbnail failed for $relPath", e)
            null
        }
    }

    fun openInputStream(relPath: String): InputStream? {
        val treeUri = store.treeUri() ?: return null
        val docId = resolveDocId(treeUri, relPath) ?: return null
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        return contentResolver.openInputStream(uri)
    }

    /** Tworzy plik w katalogu relDir i zwraca OutputStream do zapisu (upload). */
    fun createFile(relDir: String, name: String, mimeType: String): OutputStream? {
        val treeUri = store.treeUri() ?: return null
        val parentDocId = resolveDocId(treeUri, relDir) ?: return null
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentDocId)
        val newUri = DocumentsContract.createDocument(contentResolver, parentUri, mimeType, name) ?: return null
        return contentResolver.openOutputStream(newUri)
    }

    /** Rozwiązuje relativePath na documentId, schodząc segment po segmencie. */
    private fun resolveDocId(treeUri: Uri, relPath: String): String? {
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        if (relPath.isEmpty()) return rootId
        docIdCache[relPath]?.let { return it }

        var currentId = rootId
        var currentPath = ""
        for (segment in SafTreeStore.pathSegments(relPath)) {
            currentPath = SafTreeStore.childPath(currentPath, segment)
            val cached = docIdCache[currentPath]
            if (cached != null) { currentId = cached; continue }
            val found = findChildId(treeUri, currentId, segment) ?: return null
            docIdCache[currentPath] = found
            currentId = found
        }
        return currentId
    }

    private fun findChildId(treeUri: Uri, parentId: String, name: String): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (c.moveToNext()) {
                if (c.getString(nameCol) == name) return c.getString(idCol)
            }
        }
        return null
    }
}
```

- [ ] **Step 2: Zbuduj — ma się skompilować**

Run: `cd android/Airbridge && ./gradlew compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/files/FilesProvider.kt
git commit -m "feat(files): FilesProvider for SAF tree listing, thumbnails and IO"
```

---

## Task 5: Android — grant SAF w wizardzie uprawnień

**Files:**
- Modify: wizard uprawnień (zlokalizuj — patrz Step 1)

**PRZECZYTAJ NAJPIERW:** Znajdź ekran wizarda z przyciskami per-feature.
Run: `cd android/Airbridge && grep -rl "READ_SMS\|ActivityResultContracts\|registerForActivityResult\|requestPermissions" app/src/main/java --include=*.kt`
Otwórz plik(i) i naśladuj wzorzec istniejącego przycisku uprawnień (np. dla SMS/Galerii).

- [ ] **Step 1: Zlokalizuj wizard i wzorzec przycisku**

Przeczytaj plik wizarda zwrócony przez grep powyżej. Zidentyfikuj jak dodaje się: (a) przycisk, (b) launcher wyniku, (c) callback zapisujący stan uprawnienia.

- [ ] **Step 2: Dodaj launcher `ACTION_OPEN_DOCUMENT_TREE`**

W ekranie wizarda (Compose) dodaj launcher i przycisk „Pliki". Wzorzec (dostosuj nazwy do pliku):

```kotlin
val context = LocalContext.current
val safStore = remember { SafTreeStore(context) }
var hasFilesGrant by remember { mutableStateOf(safStore.hasGrant()) }

val treeLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.OpenDocumentTree()
) { uri ->
    if (uri != null) {
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        safStore.saveTreeUri(uri)
        hasFilesGrant = true
    }
}
```

Przycisk (naśladuj styl istniejących przycisków uprawnień w tym pliku):

```kotlin
PermissionButton(
    title = "Pliki",
    description = "Przeglądanie i przesyłanie plików telefonu z komputera Mac",
    granted = hasFilesGrant,
    onClick = { treeLauncher.launch(null) }
)
```

Importy: `android.content.Intent`, `androidx.activity.compose.rememberLauncherForActivityResult`, `androidx.activity.result.contract.ActivityResultContracts`, `androidx.compose.ui.platform.LocalContext`, `com.airbridge.files.SafTreeStore`.

- [ ] **Step 3: Zbuduj — ma się skompilować**

Run: `cd android/Airbridge && ./gradlew compileDebugKotlin`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add -A android/Airbridge/app/src/main/java
git commit -m "feat(files): SAF tree grant button in permissions wizard"
```

---

## Task 6: Android — handler requestów plików w `AirbridgeService`

**Files:**
- Modify: `android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt`

**PRZECZYTAJ NAJPIERW:** `AirbridgeService.kt`, funkcja `handleIncomingMessage` (ok. linii 557-838) — zobacz jak `GalleryRequest` woła `galleryProvider` i odsyła `webSocketClient.send(...)`, oraz jak realizowany jest transfer pliku Android→Mac (binary chunks) dla `GalleryDownloadRequest`/wysyłki. Naśladuj DOKŁADNIE ten wzorzec wysyłki dla `FileDownloadRequest`.

- [ ] **Step 1: Dodaj `filesProvider` jako pole serwisu**

Obok `galleryProvider` (znajdź jego deklarację) dodaj:

```kotlin
    private val filesProvider by lazy { FilesProvider(contentResolver, SafTreeStore(this)) }
```

Import: `com.airbridge.files.FilesProvider`, `com.airbridge.files.SafTreeStore`.

- [ ] **Step 2: Dodaj gałęzie w `handleIncomingMessage`**

W `when (message)` dodaj (naśladuj sąsiedni `is Message.GalleryRequest`):

```kotlin
            is Message.FilesListRequest -> {
                if (!filesProvider.hasGrant()) {
                    webSocketClient.send(Message.FilesListResponse(
                        path = message.path, entries = emptyList(), totalCount = 0,
                        page = message.page, needsPermission = true
                    ))
                } else {
                    val (entries, total) = filesProvider.listDir(message.path, message.page, message.pageSize)
                    webSocketClient.send(Message.FilesListResponse(
                        path = message.path, entries = entries, totalCount = total,
                        page = message.page, needsPermission = false
                    ))
                }
            }
            is Message.FileThumbnailRequest -> {
                val data = filesProvider.getThumbnail(message.path)
                if (data != null) {
                    webSocketClient.send(Message.FileThumbnailResponse(path = message.path, data = data))
                }
            }
            is Message.FileDownloadRequest -> {
                sendFileToMac(message.transferId, message.path)
            }
```

- [ ] **Step 3: Dodaj `sendFileToMac` (streaming Android→Mac)**

Naśladuj istniejący transfer Android→Mac (binary chunk: 36-bajtowy transferId + 4-bajtowy big-endian chunkIndex + dane — zgodnie z `FileTransferService.handleBinaryChunk` na Macu). Otwórz strumień przez `filesProvider.openInputStream(path)`, najpierw wyślij `Message.FileTransferStart(...)` (nazwa = ostatni segment ścieżki, `totalSize`, `totalChunks`), potem chunki binarne, na końcu `Message.FileTransferComplete(...)`. **Użyj tej samej funkcji wysyłki chunków, której używa istniejący kod** — znajdź ją czytając jak realizowany jest wychodzący transfer pliku w tym serwisie i wywołaj ją z `InputStream` z `filesProvider`.

Jeśli istniejąca wysyłka działa wyłącznie na `Uri`/`File`, dodaj wariant przyjmujący `InputStream` + `name` + `size`, reużywając identycznego framingu chunków.

- [ ] **Step 4: Obsłuż `destinationDir` przy odbiorze uploadu (Mac→Android)**

Znajdź gałąź obsługującą `Message.FileTransferOffer` / pobranie pliku z HTTP serwera Maca i zapis na telefonie. Gdy `offer.destinationDir != null`, zapisz strumień przez `filesProvider.createFile(offer.destinationDir, offer.filename, offer.mimeType)` zamiast domyślnej lokalizacji (Downloads). Gdy `null` — zachowanie bez zmian.

- [ ] **Step 5: Zbuduj — ma się skompilować**

Run: `cd android/Airbridge && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
git add android/Airbridge/app/src/main/java/com/airbridge/service/AirbridgeService.kt
git commit -m "feat(files): handle files list/thumbnail/download + upload destination on Android"
```

---

## Task 7: macOS — `FilesBrowserService`

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift`

Wzorzec 1:1 jak `GalleryService.swift` (cache + `MessageHandler`).

- [ ] **Step 1: Napisz `FilesBrowserService`**

Utwórz `macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift`:

```swift
import Foundation
import AppKit
import Protocol

@Observable
@MainActor
final class FilesBrowserService: MessageHandler {

    private(set) var currentPath: String = ""
    private(set) var entries: [FileEntry] = []
    private(set) var totalCount: Int = 0
    private(set) var currentPage: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var needsPermission: Bool = false
    private(set) var thumbnails: [String: NSImage] = [:]   // relativePath -> thumb

    private var requestedThumbnails: Set<String> = []
    private let pageSize = 200
    private weak var connectionService: ConnectionService?
    private weak var fileTransferService: FileTransferService?

    func configure(connectionService: ConnectionService, fileTransferService: FileTransferService) {
        self.connectionService = connectionService
        self.fileTransferService = fileTransferService
    }

    /// Breadcrumb segmenty bieżącej ścieżki.
    var breadcrumbs: [String] {
        currentPath.split(separator: "/").map(String.init)
    }

    // MARK: - Navigation

    func open(path: String, page: Int = 0) {
        guard let connectionService, connectionService.isConnected else { return }
        isLoading = true
        if page == 0 {
            currentPath = path
            entries = []
            thumbnails = [:]
            requestedThumbnails = []
        }
        let message = Message.filesListRequest(path: path, page: page, pageSize: pageSize)
        Task { try? await connectionService.broadcast(message) }
    }

    func reload() { open(path: currentPath) }

    func navigateUp() {
        guard !currentPath.isEmpty else { return }
        var segments = currentPath.split(separator: "/").map(String.init)
        segments.removeLast()
        open(path: segments.joined(separator: "/"))
    }

    /// Wejście do folderu lub pobranie pliku.
    func activate(_ entry: FileEntry) {
        if entry.isDirectory {
            open(path: entry.relativePath)
        } else {
            download(entry)
        }
    }

    func loadNextPage() {
        let nextPage = currentPage + 1
        let totalPages = (totalCount + pageSize - 1) / pageSize
        guard nextPage < totalPages, !isLoading else { return }
        open(path: currentPath, page: nextPage)
    }

    // MARK: - Thumbnails

    func requestThumbnail(_ entry: FileEntry) {
        guard !entry.isDirectory,
              entry.mimeType.hasPrefix("image/"),
              thumbnails[entry.relativePath] == nil,
              !requestedThumbnails.contains(entry.relativePath),
              let connectionService else { return }
        requestedThumbnails.insert(entry.relativePath)
        Task { try? await connectionService.broadcast(.fileThumbnailRequest(path: entry.relativePath)) }
    }

    // MARK: - Transfer

    func download(_ entry: FileEntry) {
        guard let connectionService else { return }
        let transferId = UUID().uuidString
        Task { try? await connectionService.broadcast(.fileDownloadRequest(transferId: transferId, path: entry.relativePath)) }
    }

    func upload(urls: [URL]) {
        guard let fileTransferService else { return }
        for url in urls {
            fileTransferService.sendFile(url: url, destinationDir: currentPath)
        }
    }

    // MARK: - MessageHandler

    func handleMessage(_ message: Message) {
        switch message {
        case .filesListResponse(let path, let newEntries, let total, let page, let needsPerm):
            guard path == currentPath else { return }
            needsPermission = needsPerm
            if page == 0 {
                entries = newEntries
            } else {
                entries.append(contentsOf: newEntries)
            }
            totalCount = total
            currentPage = page
            isLoading = false
            for entry in newEntries { requestThumbnail(entry) }

        case .fileThumbnailResponse(let path, let data):
            if let imageData = Data(base64Encoded: data), let image = NSImage(data: imageData) {
                thumbnails[path] = image
            }

        default:
            break
        }
    }
}
```

- [ ] **Step 2: Zbuduj — ma failować na `sendFile(url:destinationDir:)`**

Run: `cd macos/Airbridge && swift build`
Expected: FAIL — `FileTransferService.sendFile` nie ma jeszcze `destinationDir` (dodane w Task 8).

- [ ] **Step 3: Commit (po Task 8 zbuduje się czysto — tu commit tylko service)**

Wstrzymaj commit do Task 8 (build musi przejść). Przejdź do Task 8.

---

## Task 8: macOS — upload z `destinationDir` w `FileTransferService` + routing/rejestracja

**Files:**
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/FileTransferService.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift`

- [ ] **Step 1: `sendFile` przyjmuje opcjonalny `destinationDir`**

W `FileTransferService.swift` zmień `sendFile` (linia 141) i przepchnij katalog do oferty. Najprościej: kolejka trzyma pary.

Zmień pole kolejki (linia 34):

```swift
    @ObservationIgnored private var sendQueue: [(url: URL, destinationDir: String?)] = []
```

Zmień `sendFile` (linia 141-144):

```swift
    func sendFile(url: URL, destinationDir: String? = nil) {
        sendQueue.append((url, destinationDir))
        processQueue()
    }
```

Zmień `processQueue` (linia 155-160), aby wyciągał parę:

```swift
    private func processQueue() {
        guard !isSendingFromQueue, !sendQueue.isEmpty else { return }
        isSendingFromQueue = true
        let item = sendQueue.removeFirst()
        sendSingleFile(url: item.url, destinationDir: item.destinationDir)
    }
```

Zmień sygnaturę `sendSingleFile` (linia 162):

```swift
    private func sendSingleFile(url: URL, destinationDir: String?) {
```

Zmień konstrukcję oferty (linia 235, ustawioną tymczasowo w Task 1 Step 9) na:

```swift
            let offer = Message.fileTransferOffer(transferId: transferId, filename: filename, mimeType: mime, fileSize: fileSize, destinationDir: destinationDir)
```

- [ ] **Step 2: Zarejestruj handler plików w `ConnectionService`**

W `ConnectionService.swift`:

Dodaj pole (po linii 57, `smsHandler`):

```swift
    private var filesHandler: MessageHandler?
```

Rozszerz `registerHandlers` (linia 59-69):

```swift
    func registerHandlers(
        clipboard: MessageHandler,
        fileTransfer: MessageHandler,
        gallery: MessageHandler,
        sms: MessageHandler,
        files: MessageHandler
    ) {
        self.clipboardHandler = clipboard
        self.fileTransferHandler = fileTransfer
        self.galleryHandler = gallery
        self.smsHandler = sms
        self.filesHandler = files
    }
```

Dodaj routing w `routeAuthenticatedMessage` (po linii 239, gałąź sms):

```swift
        case .filesListResponse, .fileThumbnailResponse:
            filesHandler?.handleMessage(message)
```

- [ ] **Step 3: Utwórz i podłącz `FilesBrowserService` w `AirbridgeApp`**

W `AirbridgeApp.swift`:

Dodaj `@State` (po linii 26, `smsService`):

```swift
    @State private var filesBrowserService: FilesBrowserService
```

W `init()` (po linii 38, `let sms = SmsService()`):

```swift
        let filesBrowser = FilesBrowserService()
```

Konfiguracja (po linii 47, `sms.configure(...)`):

```swift
        filesBrowser.configure(connectionService: connection, fileTransferService: fileTransfer)
```

Zmień `registerHandlers` (linia 50):

```swift
        connection.registerHandlers(clipboard: clipboard, fileTransfer: fileTransfer, gallery: gallery, sms: sms, files: filesBrowser)
```

Przypisz state (po linii 60, `_smsService = ...`):

```swift
        _filesBrowserService = State(initialValue: filesBrowser)
```

Przekaż do `MainWindow` w `body` (po linii 91, `smsService: smsService,`):

```swift
                        filesBrowserService: filesBrowserService,
```

- [ ] **Step 4: Zbuduj — ma przejść**

Run: `cd macos/Airbridge && swift build`
Expected: BUILD SUCCESSFUL (oczekuj błędu o brakującym argumencie `filesBrowserService` w `MainWindow` — naprawiany w Task 9; jeśli blokuje, dodaj parametr z Task 9 Step 1 najpierw).

- [ ] **Step 5: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Services/FilesBrowserService.swift macos/Airbridge/Sources/AirbridgeApp/Services/FileTransferService.swift macos/Airbridge/Sources/AirbridgeApp/Services/ConnectionService.swift macos/Airbridge/Sources/AirbridgeApp/AirbridgeApp.swift
git commit -m "feat(files): FilesBrowserService + upload destinationDir + routing wiring (macOS)"
```

---

## Task 9: macOS — `FilesBrowserView` + nawigacja (tab Pliki)

**Files:**
- Create: `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Navigation/NavigationItem.swift`
- Modify: `macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift`

- [ ] **Step 1: Dodaj `case files` do `NavigationItem`**

W `NavigationItem.swift`: dodaj `case files` (po `gallery`, linia 7), do `iconName` `case .files: return "folder.fill"`, do `title` `case .files: return L10n.isPL ? "Pliki" : "Files"`, i do `topItems` (linia 36) wstaw `.files` po `.gallery`.

- [ ] **Step 2: Napisz `FilesBrowserView`**

Utwórz `macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import Protocol

struct FilesBrowserView: View {
    let filesBrowserService: FilesBrowserService
    let connectionService: ConnectionService

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            content
        }
        .onAppear { filesBrowserService.open(path: "") }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected { filesBrowserService.open(path: "") }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Button { filesBrowserService.open(path: "") } label: {
                Image(systemName: "internaldrive")
            }
            .buttonStyle(.borderless)

            ForEach(Array(filesBrowserService.breadcrumbs.enumerated()), id: \.offset) { index, segment in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(segment) {
                    let path = filesBrowserService.breadcrumbs.prefix(index + 1).joined(separator: "/")
                    filesBrowserService.open(path: path)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if filesBrowserService.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if filesBrowserService.needsPermission {
            permissionEmptyState
        } else {
            List(filesBrowserService.entries) { entry in
                FileRow(entry: entry, thumbnail: filesBrowserService.thumbnails[entry.relativePath])
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { filesBrowserService.activate(entry) }
                    .onAppear { filesBrowserService.requestThumbnail(entry) }
            }
            .listStyle(.inset)
        }
    }

    private var permissionEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(L10n.isPL ? "Przyznaj dostęp do plików na telefonie" : "Grant file access on your phone")
                .font(.headline)
            Text(L10n.isPL
                 ? "Na telefonie otwórz AirBridge → wizard uprawnień → „Pliki" i zezwól na dostęp do Pamięci wewnętrznej."
                 : "On your phone open AirBridge → permissions → \"Files\" and allow access to internal storage.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(L10n.isPL ? "Odśwież" : "Refresh") { filesBrowserService.reload() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !filesBrowserService.needsPermission else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { filesBrowserService.upload(urls: urls) }
        }
        return true
    }
}

private struct FileRow: View {
    let entry: FileEntry
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                if !entry.isDirectory {
                    Text(Self.sizeFormatter.string(fromByteCount: entry.size))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: entry.isDirectory ? "folder.fill" : Self.symbol(for: entry.mimeType))
                .frame(width: 28, height: 28)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
        }
    }

    private static func symbol(for mime: String) -> String {
        switch {
        case mime.hasPrefix("image/"): return "photo"
        case mime.hasPrefix("video/"): return "film"
        case mime.hasPrefix("audio/"): return "music.note"
        case mime == "application/pdf": return "doc.richtext"
        case mime.hasPrefix("text/"): return "doc.text"
        default: return "doc"
        }
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter(); f.countStyle = .file; return f
    }()
}
```

(Uwaga: `switch {` powyżej to skrót — zamień na `switch true {` lub `if/else` jeśli kompilator marudzi. Preferuj `if mime.hasPrefix("image/") { ... }` łańcuch.)

- [ ] **Step 3: Dodaj `Tab(.files)` w `MainWindow`**

W `MainWindow.swift`: dodaj property `let filesBrowserService: FilesBrowserService` (po `galleryService`, linia 11). Dodaj Tab po galerii (po linii 48):

```swift
            Tab(NavigationItem.files.title, systemImage: "folder.fill", value: .files) {
                ScreenContainer(scroll: false) {
                    FilesBrowserView(filesBrowserService: filesBrowserService, connectionService: connectionService)
                }
            }
```

- [ ] **Step 4: Popraw `switch true`/if-else w `FileRow.symbol`**

Zamień ciało `symbol(for:)` na łańcuch `if`:

```swift
    private static func symbol(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "music.note" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }
```

- [ ] **Step 5: Zbuduj — ma przejść**

Run: `cd macos/Airbridge && swift build`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
git add macos/Airbridge/Sources/AirbridgeApp/Views/FilesBrowserView.swift macos/Airbridge/Sources/AirbridgeApp/Navigation/NavigationItem.swift macos/Airbridge/Sources/AirbridgeApp/Navigation/MainWindow.swift
git commit -m "feat(files): FilesBrowserView Finder-like UI + Files tab (macOS)"
```

---

## Task 10: Integracja manualna na urządzeniu

**Files:** brak (weryfikacja end-to-end)

- [ ] **Step 1: Zbuduj i zainstaluj APK**

Run: `cd android/Airbridge && ./gradlew assembleDebug && adb -s RFCY71BEL0T install -r app/build/outputs/apk/debug/app-debug.apk`
Expected: `Success`.

- [ ] **Step 2: Odpal apkę macOS**

Run: `bash scripts/dev-install.sh`
Expected: aplikacja startuje, telefon paruje (`isConnected`).

- [ ] **Step 3: Grant SAF na telefonie**

Na telefonie: AirBridge → wizard uprawnień → „Pliki" → zezwól na dostęp do Pamięci wewnętrznej.
Expected: po grancie wpis utrwalony (po restarcie apki dalej działa).

- [ ] **Step 4: Browse**

Na Macu otwórz tab „Pliki".
Expected: listing korzenia (Download, DCIM, Documents…), wejście w folder, breadcrumb działa, thumbnaile obrazów się ładują.

- [ ] **Step 5: Download**

Dwuklik pliku (np. PDF w Download).
Expected: plik ląduje w `~/Downloads/AirBridge`, island progresu pokazuje transfer.

- [ ] **Step 6: Upload**

Przeciągnij plik z Findera na widok Pliki (będąc w jakimś folderze).
Expected: plik pojawia się w tym folderze na telefonie (zweryfikuj `adb -s RFCY71BEL0T shell ls /sdcard/<folder>`), island progresu pokazuje wysyłkę.

- [ ] **Step 7: Empty-state braku grantu**

(Opcjonalnie) Cofnij grant na telefonie (Ustawienia → Aplikacje → AirBridge → uprawnienia / wyczyść) i odśwież.
Expected: Mac pokazuje empty-state „Przyznaj dostęp do plików na telefonie".

---

## Self-Review (wypełnione przy pisaniu planu)

- **Spec coverage:** browse (Task 4,6,7,9), download (Task 6,7,8,9), upload (Task 6,8,9), SAF grant (Task 3,5), thumbnaile (Task 4,7,9), empty-state braku grantu (Task 6,7,9), protokół zsynchronizowany (Task 1,2). ✓
- **Type consistency:** `FileEntry`/`FileTransferOffer.destinationDir` identyczne po obu stronach; `sendFile(url:destinationDir:)` zdefiniowane w Task 8 i użyte w Task 7. Pola JSON snake_case spójne. ✓
- **Znane luki wymagające czytania kodu:** Task 5 (wizard uprawnień), Task 6 Step 3-4 (framing chunków Android→Mac + zapis uploadu) — oznaczone „PRZECZYTAJ NAJPIERW", bo dokładny istniejący kod nie był cytowany. Implementujący agent MUSI przeczytać wskazane funkcje przed pisaniem.
