package com.airbridge.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import javax.crypto.AEADBadTagException
import javax.crypto.KeyGenerator

class KeyCryptoTest {

    private fun jvmKey() = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test
    fun `encrypt then decrypt round-trips`() {
        val key = jvmKey()
        val plaintext = "private-key-bytes".toByteArray()
        val blob = KeyCrypto.encrypt(key, plaintext)
        assertArrayEquals(plaintext, KeyCrypto.decrypt(key, blob))
    }

    @Test
    fun `each encryption uses a fresh IV`() {
        val key = jvmKey()
        val a = KeyCrypto.encrypt(key, byteArrayOf(1, 2, 3))
        val b = KeyCrypto.encrypt(key, byteArrayOf(1, 2, 3))
        org.junit.Assert.assertFalse(a.contentEquals(b))
    }

    @Test
    fun `tampered blob fails authentication`() {
        val key = jvmKey()
        val blob = KeyCrypto.encrypt(key, byteArrayOf(9, 9, 9))
        blob[blob.size - 1] = (blob[blob.size - 1].toInt() xor 1).toByte()
        assertThrows(AEADBadTagException::class.java) { KeyCrypto.decrypt(key, blob) }
    }
}
