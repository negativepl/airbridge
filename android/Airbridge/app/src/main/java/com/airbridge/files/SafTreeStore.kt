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
