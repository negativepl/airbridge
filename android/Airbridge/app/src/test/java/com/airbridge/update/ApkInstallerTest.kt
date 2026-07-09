package com.airbridge.update

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.security.MessageDigest

class ApkInstallerTest {
    @Test fun `sha256Hex matches MessageDigest`() {
        val tempDir = kotlin.io.path.createTempDirectory().toFile()
        val f = File(tempDir, "test.bin").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val expected = MessageDigest.getInstance("SHA-256").digest(byteArrayOf(1, 2, 3))
            .joinToString("") { "%02x".format(it) }
        assertEquals(expected, ApkInstaller.sha256Hex(f))
    }

    @Test fun `download verifies checksum`() = runBlocking {
        val payload = ByteArray(1024) { it.toByte() }
        val goodHash = MessageDigest.getInstance("SHA-256").digest(payload)
            .joinToString("") { "%02x".format(it) }
        val server = MockWebServer().apply {
            enqueue(MockResponse().setBody(okio.Buffer().write(payload)))
            enqueue(MockResponse().setBody(okio.Buffer().write(payload)))
            start()
        }
        val dir = kotlin.io.path.createTempDirectory().toFile()
        val ok = ApkInstaller.downloadTo(
            url = server.url("/a.apk").toString(),
            expectedSha256 = goodHash, dest = File(dir, "ok.apk"), onProgress = {}
        )
        assertNotNull(ok)
        val bad = ApkInstaller.downloadTo(
            url = server.url("/a.apk").toString(),
            expectedSha256 = "deadbeef", dest = File(dir, "bad.apk"), onProgress = {}
        )
        assertNull(bad)
        server.close()
    }
}
