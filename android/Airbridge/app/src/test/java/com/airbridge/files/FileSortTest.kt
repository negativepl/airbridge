package com.airbridge.files

import com.airbridge.protocol.FileEntry
import org.junit.Assert.assertEquals
import org.junit.Test

class FileSortTest {
    private fun f(name: String, dir: Boolean = false, size: Long = 0, modified: Long = 0) =
        FileEntry(name, name, dir, size, modified, if (dir) "inode/directory" else "text/plain")

    private val sample = listOf(
        f("banana.txt", size = 30, modified = 200),
        f("Apple", dir = true, size = 0, modified = 100),
        f("cherry.txt", size = 10, modified = 300),
        f("zebra", dir = true, size = 5, modified = 50)
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
        val r = sortFileEntries(sample, "size", "asc", foldersFirst = false).map { it.name }
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }

    @Test fun modifiedDescFoldersFirst() {
        val r = sortFileEntries(sample, "modified", "desc", foldersFirst = true).map { it.name }
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }

    @Test fun typeAscGroupsByExtension() {
        val items = listOf(
            f("report.pdf", size = 1),
            f("photo.png", size = 2),
            f("notes.md", size = 3),
            f("Makefile", size = 4),        // no extension -> "" sorts first
            f("archive.pdf", size = 5)
        )
        val r = sortFileEntries(items, "type", "asc", foldersFirst = false).map { it.name }
        // "" (Makefile) < "md" < "pdf" < "png"; within pdf: archive < report by name
        assertEquals(listOf("Makefile", "notes.md", "archive.pdf", "report.pdf", "photo.png"), r)
    }
}
