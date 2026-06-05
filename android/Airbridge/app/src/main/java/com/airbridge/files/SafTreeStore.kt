package com.airbridge.files

/**
 * Czyste helpery na ścieżki względne używane przez FilesProvider.
 * Ścieżka względna używa "/" jako separatora, korzeń = "".
 *
 * (Nazwa historyczna — wcześniej trzymał też grant SAF; po przejściu na
 * MANAGE_EXTERNAL_STORAGE persystencja tree URI nie jest już potrzebna.)
 */
object SafTreeStore {

    /** Rozbija ścieżkę względną na segmenty, pomijając puste. */
    fun pathSegments(path: String): List<String> =
        path.split("/").filter { it.isNotEmpty() }

    /** Łączy katalog względny z nazwą dziecka. */
    fun childPath(dir: String, name: String): String =
        if (dir.isEmpty()) name else "$dir/$name"
}
