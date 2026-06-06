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
        val r = sortFileEntries(sample, "size", "asc", foldersFirst = false).map { it.name }
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }

    @Test fun modifiedDescFoldersFirst() {
        val r = sortFileEntries(sample, "modified", "desc", foldersFirst = true).map { it.name }
        assertEquals(listOf("Apple", "zebra", "cherry.txt", "banana.txt"), r)
    }
}
