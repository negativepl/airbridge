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

    /** Rozmiar pliku w bajtach (kolumna SIZE). -1 gdy nieznany/brak grantu. */
    fun fileSize(relPath: String): Long {
        val treeUri = store.treeUri() ?: return -1
        val docId = resolveDocId(treeUri, relPath) ?: return -1
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_SIZE),
            null, null, null
        )?.use { c ->
            val sizeCol = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            if (c.moveToFirst() && !c.isNull(sizeCol)) return c.getLong(sizeCol)
        }
        return -1
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
