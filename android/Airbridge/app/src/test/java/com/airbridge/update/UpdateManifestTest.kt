package com.airbridge.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

class UpdateManifestTest {
    private val sample = """
        {"version":"2.8.0-beta","versionCode":20800,"publishedAt":"2026-07-09",
         "android":{"url":"https://example.com/a.apk","sha256":"ab12","size":42},
         "macos":{"url":"https://example.com/a.zip","sha256":"cd34","size":43},
         "changelog":{"pl":["Punkt"],"en":["Item"]}}
    """.trimIndent()

    @Test fun `parses all fields`() {
        val m = UpdateManifest.parse(sample)
        assertEquals("2.8.0-beta", m.version)
        assertEquals(20800, m.versionCode)
        assertEquals("https://example.com/a.apk", m.android.url)
        assertEquals("ab12", m.android.sha256)
        assertEquals(42L, m.android.size)
        assertEquals(listOf("Punkt"), m.changelogPl)
        assertEquals(listOf("Item"), m.changelogEn)
    }

    @Test fun `isNewerThan compares versionCode`() {
        val m = UpdateManifest.parse(sample)
        assertTrue(m.isNewerThan(20706))
        assertFalse(m.isNewerThan(20800))
        assertFalse(m.isNewerThan(20900))
    }

    @Test fun `verifySignature accepts valid and rejects tampered`() {
        // JVM unit test: java.security has Ed25519 on JDK 15+; on-device Conscrypt
        // provides it (pairing already relies on this).
        val kp = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val bytes = sample.toByteArray()
        val sig = Signature.getInstance("Ed25519").apply { initSign(kp.private); update(bytes) }.sign()
        // Raw 32-byte key = last 32 bytes of the X.509 DER (12-byte ASN.1 prefix).
        val raw = kp.public.encoded.takeLast(32).toByteArray()
        val pubB64 = Base64.getEncoder().encodeToString(raw)
        val sigB64 = Base64.getEncoder().encodeToString(sig)
        assertTrue(UpdateManifest.verifySignature(bytes, sigB64, pubB64))
        assertFalse(UpdateManifest.verifySignature("tampered".toByteArray() + bytes, sigB64, pubB64))
    }
}
