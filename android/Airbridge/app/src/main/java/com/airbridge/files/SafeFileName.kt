package com.airbridge.files

import java.io.File

/**
 * Path-traversal protection for filenames received from the network.
 *
 * Every code path that writes a received file under a local directory must go
 * through this helper — a peer-supplied name like "../../x" must never be
 * able to escape the destination directory.
 */
object SafeFileName {

    /**
     * Returns just the final path segment of [raw] (treating both '/' and
     * '\' as separators), or null when the result is empty or a dot-name
     * ("." / "..") that could be used to escape the destination directory.
     */
    fun sanitize(raw: String): String? {
        val name = File(raw.replace('\\', '/')).name
        if (name.isEmpty() || name == "." || name == "..") return null
        return name
    }

    /**
     * Resolves [filename] inside [dir] after sanitization, then verifies the
     * canonical path still lives inside [dir]. Returns null on any escape
     * attempt.
     */
    fun resolveIn(dir: File, filename: String): File? {
        val name = sanitize(filename) ?: return null
        val target = File(dir, name)
        val dirCanonical = dir.canonicalPath
        if (!target.canonicalPath.startsWith(dirCanonical + File.separator)) return null
        return target
    }
}
