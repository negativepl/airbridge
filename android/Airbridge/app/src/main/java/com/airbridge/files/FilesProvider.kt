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
        return paginate(sorted, page, pageSize)
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
            for (f in root.walkTopDown().onFail { _, _ -> }) {   // pomiń niedostępne katalogi, kontynuuj
                if (f == root) continue
                if (f.name.lowercase().contains(needle)) {
                    // parentRel = ścieżka trafienia względem root bez ostatniego segmentu → childPath odtwarza pełną ścieżkę jak w listDir
                    val rel = f.relativeTo(root).path.replace(File.separatorChar, '/')
                    hits.add(toEntry(f, rel.substringBeforeLast('/', "")))
                    if (hits.size >= SEARCH_LIMIT) break
                }
            }
        } catch (e: Exception) {
            Log.e("FilesProvider", "searchDir walk failed for '$query'", e)
        }
        val sorted = sortFileEntries(hits, sortBy, sortDir, foldersFirst)
        return paginate(sorted, page, pageSize)
    }

    /** Wytnij stronę `page` o rozmiarze `pageSize` z posortowanej listy. Zwraca (strona, totalCount). */
    private fun <T> paginate(sorted: List<T>, page: Int, pageSize: Int): Pair<List<T>, Int> {
        val from = (page * pageSize).coerceAtMost(sorted.size)
        val to = (from + pageSize).coerceAtMost(sorted.size)
        return Pair(sorted.subList(from, to).toList(), sorted.size)
    }

    companion object {
        /** Górny limit trafień search, chroni przed pełnym walkiem /sdcard. */
        const val SEARCH_LIMIT = 500
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

    /** Usuwa plik lub folder (rekurencyjnie). Zwraca true gdy usunięto.
     *  Pusty relPath (korzeń /sdcard) jest odrzucany. Ścieżki wychodzące poza
     *  /sdcard (np. z ".." lub absolutne) są odrzucane (canonical-path guard).
     *
     *  Uwaga: deleteRecursively() przy częściowym niepowodzeniu (np. zablokowany
     *  plik potomny) usuwa co się da i zwraca false — wynik false może więc oznaczać
     *  częściowe usunięcie, nie tylko "nic nie usunięto".
     */
    fun delete(relPath: String): Boolean {
        if (relPath.isBlank()) return false
        val target = File(root, relPath)
        if (!target.exists()) return false
        val rootCanon = root.canonicalPath
        val targetCanon = try { target.canonicalPath } catch (e: Exception) {
            Log.e("FilesProvider", "delete canonicalPath failed for $relPath", e)
            return false
        }
        // Tylko ściśle wewnątrz /sdcard (odrzuca też sam korzeń i ucieczki przez "..").
        if (!targetCanon.startsWith(rootCanon + File.separator)) return false
        return try {
            if (target.isDirectory) target.deleteRecursively() else target.delete()
        } catch (e: Exception) {
            Log.e("FilesProvider", "delete failed for $relPath", e)
            false
        }
    }

    private fun mimeFromName(name: String): String {
        val ext = name.substringAfterLast('.', "")
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase())
            ?: "application/octet-stream"
    }
}
