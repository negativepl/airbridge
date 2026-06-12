package com.airbridge.security

import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM wrap/unwrap for the Ed25519 private key blob.
 * Blob layout: 12-byte IV || ciphertext+tag. Pure JVM logic — the Keystore
 * master key is resolved by the caller (KeyManager) so this stays unit-testable.
 */
object KeyCrypto {
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128

    fun encrypt(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(plaintext)
    }

    fun decrypt(key: SecretKey, blob: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val spec = GCMParameterSpec(TAG_BITS, blob, 0, IV_BYTES)
        cipher.init(Cipher.DECRYPT_MODE, key, spec)
        return cipher.doFinal(blob, IV_BYTES, blob.size - IV_BYTES)
    }
}
