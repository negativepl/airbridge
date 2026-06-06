package com.airbridge.files

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Environment
import android.util.Base64
import android.util.Log
import android.webkit.MimeTypeMap
import com.airbridge.protocol.FileEntry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

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

/**
 * Provides browsing/download/upload over the whole external storage (/sdcard)
 * via plain java.io.File. Requires MANAGE_EXTERNAL_STORAGE (All Files Access).
 * Relative paths use "/" as separator; root ("") = /sdcard.
 */
class FilesProvider(
    private val contentResolver: ContentResolver
) {
    private val root: File = Environment.getExternalStorageDirectory()

    fun hasGrant(): Boolean = Environment.isExternalStorageManager()

    /** Listing katalogu (relPath="" = korzeń /sdcard). Zwraca (entries, totalCount). */
    fun listDir(relPath: String, page: Int, pageSize: Int): Pair<List<FileEntry>, Int> {
        val dir = File(root, relPath)
        val children = dir.listFiles() ?: return Pair(emptyList(), 0)

        val all = children.map { f ->
            val isDir = f.isDirectory
            FileEntry(
                name = f.name,
                relativePath = SafTreeStore.childPath(relPath, f.name),
                isDirectory = isDir,
                size = if (isDir) 0 else f.length(),
                modified = f.lastModified(),
                mimeType = if (isDir) "inode/directory" else mimeFromName(f.name)
            )
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

    /**
     * Statystyki folderu: liczba bezpośrednich podfolderów i plików +
     * rozmiar rekurencyjny (suma długości wszystkich plików w drzewie).
     * Zwraca Triple(dirCount, fileCount, totalSize).
     */
    fun folderStats(relPath: String): Triple<Int, Int, Long> {
        val dir = File(root, relPath)
        val children = dir.listFiles() ?: return Triple(0, 0, 0L)
        var dirCount = 0
        var fileCount = 0
        for (c in children) {
            if (c.isDirectory) dirCount++ else fileCount++
        }
        var totalSize = 0L
        try {
            dir.walkTopDown().forEach { f -> if (f.isFile) totalSize += f.length() }
        } catch (e: Exception) {
            Log.e("FilesProvider", "folderStats walk failed for $relPath", e)
        }
        return Triple(dirCount, fileCount, totalSize)
    }

    /** Thumbnail dla obrazów (skala 400px, JPEG q75, base64). null dla nie-obrazów. */
    fun getThumbnail(relPath: String): String? {
        val file = File(root, relPath)
        if (!file.exists() || file.isDirectory) return null
        if (!mimeFromName(file.name).startsWith("image/")) return null
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, opts)
            var sample = 1
            while (opts.outWidth / sample > 800 || opts.outHeight / sample > 800) sample *= 2
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = BitmapFactory.decodeFile(file.absolutePath, decodeOpts) ?: return null
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

    /** file:// Uri dla pliku (do uploadu HTTP). null gdy plik nie istnieje. */
    fun fileUri(relPath: String): Uri? {
        val file = File(root, relPath)
        return if (file.exists()) Uri.fromFile(file) else null
    }

    /** Tworzy plik w katalogu relDir i zwraca (Uri, OutputStream) do zapisu (upload).
     *  Caller receives the Uri so it can delete the file on write failure. */
    fun createFile(relDir: String, name: String, mimeType: String): Pair<Uri, OutputStream>? {
        return try {
            val dir = File(root, relDir)
            dir.mkdirs()
            val f = File(dir, name)
            Pair(Uri.fromFile(f), FileOutputStream(f))
        } catch (e: Exception) {
            Log.e("FilesProvider", "createFile failed for $relDir/$name", e)
            null
        }
    }

    private fun mimeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "")
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase())
            ?: "application/octet-stream"
    }
}
