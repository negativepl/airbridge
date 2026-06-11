package com.airbridge.files

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SafeFileNameTest {

    // --- sanitize ---

    @Test
    fun `plain filename passes through`() {
        assertEquals("photo.jpg", SafeFileName.sanitize("photo.jpg"))
    }

    @Test
    fun `traversal is reduced to last segment`() {
        assertEquals("passwd", SafeFileName.sanitize("../../etc/passwd"))
        assertEquals("c.txt", SafeFileName.sanitize("a/b/c.txt"))
        assertEquals("passwd", SafeFileName.sanitize("/etc/passwd"))
    }

    @Test
    fun `windows separators are treated as separators`() {
        assertEquals("b.txt", SafeFileName.sanitize("a\\..\\b.txt"))
        assertNull(SafeFileName.sanitize("a\\.."))
    }

    @Test
    fun `dot names and empty are rejected`() {
        assertNull(SafeFileName.sanitize("."))
        assertNull(SafeFileName.sanitize(".."))
        assertNull(SafeFileName.sanitize("a/.."))
        assertNull(SafeFileName.sanitize(""))
        assertNull(SafeFileName.sanitize("/"))
    }

    // --- resolveIn ---

    private fun tempDir(): File = Files.createTempDirectory("safefilename").toFile()

    @Test
    fun `resolveIn keeps file inside directory`() {
        val dir = tempDir()
        val file = SafeFileName.resolveIn(dir, "report.pdf")
        assertEquals(File(dir, "report.pdf").canonicalPath, file?.canonicalPath)
    }

    @Test
    fun `resolveIn collapses traversal to last segment`() {
        val dir = tempDir()
        val file = SafeFileName.resolveIn(dir, "../../../etc/passwd")
        assertEquals(File(dir, "passwd").canonicalPath, file?.canonicalPath)
    }

    @Test
    fun `resolveIn rejects dot names`() {
        val dir = tempDir()
        assertNull(SafeFileName.resolveIn(dir, ".."))
        assertNull(SafeFileName.resolveIn(dir, "."))
        assertNull(SafeFileName.resolveIn(dir, ""))
    }
}
