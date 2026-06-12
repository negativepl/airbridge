package com.airbridge.security

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyFactory
import java.security.KeyStore
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.UUID
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class KeyManager(context: Context) {

    companion object {
        private const val MASTER_KEY_ALIAS = "airbridge_master_key"
        private const val PREF_ENC = "private_key_enc"
        private const val PREF_PLAINTEXT = "private_key_base64" // legacy

        /** SHA-256 hex fingerprint of a base64-encoded raw public key. */
        fun fingerprintOf(publicKeyBase64: String): String {
            val keyBytes = Base64.decode(publicKeyBase64, Base64.NO_WRAP)
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            return digest.digest(keyBytes).joinToString("") { "%02x".format(it) }
        }
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences("airbridge_keys", Context.MODE_PRIVATE)

    fun getOrCreateDeviceId(): String {
        val existing = prefs.getString("device_id", null)
        if (existing != null) return existing
        val newId = UUID.randomUUID().toString()
        prefs.edit().putString("device_id", newId).apply()
        return newId
    }

    fun getOrCreatePublicKey(): String {
        val existing = prefs.getString("public_key_base64", null)
        if (existing != null) return existing
        generateKeyPair()
        return prefs.getString("public_key_base64", null)!!
    }

    fun getRawPublicKeyBytes(): ByteArray {
        val pubKeyBase64 = getOrCreatePublicKey()
        val x509Bytes = Base64.decode(pubKeyBase64, Base64.NO_WRAP)
        // Ed25519 X.509 encoding: 12-byte ASN.1 prefix + 32-byte raw key
        return x509Bytes.copyOfRange(12, 44)
    }

    fun getRawPublicKeyBase64(): String {
        return Base64.encodeToString(getRawPublicKeyBytes(), Base64.NO_WRAP)
    }

    fun getPublicKeyFingerprint(): String = fingerprintOf(getRawPublicKeyBase64())

    fun sign(data: ByteArray): String {
        val privKeyBytes = loadPrivateKeyBytes()
        val keySpec = PKCS8EncodedKeySpec(privKeyBytes)
        val keyFactory = KeyFactory.getInstance("Ed25519")
        val privateKey = keyFactory.generatePrivate(keySpec)
        val signature = Signature.getInstance("Ed25519")
        signature.initSign(privateKey)
        signature.update(data)
        return Base64.encodeToString(signature.sign(), Base64.NO_WRAP)
    }

    fun verify(publicKeyBase64: String, data: ByteArray, signatureBase64: String): Boolean {
        return try {
            val pubKeyBytes = Base64.decode(publicKeyBase64, Base64.NO_WRAP)
            val keySpec = X509EncodedKeySpec(pubKeyBytes)
            val keyFactory = KeyFactory.getInstance("Ed25519")
            val publicKey = keyFactory.generatePublic(keySpec)
            val sig = Signature.getInstance("Ed25519")
            sig.initVerify(publicKey)
            sig.update(data)
            sig.verify(Base64.decode(signatureBase64, Base64.NO_WRAP))
        } catch (e: Exception) {
            false
        }
    }

    private fun masterKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(MASTER_KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    /** One-time migration: encrypt a legacy plaintext private key, drop the plaintext. */
    private fun migratePrivateKeyIfNeeded(masterKey: SecretKey) {
        val plaintext = prefs.getString(PREF_PLAINTEXT, null) ?: return
        val blob = KeyCrypto.encrypt(masterKey, Base64.decode(plaintext, Base64.NO_WRAP))
        prefs.edit()
            .putString(PREF_ENC, Base64.encodeToString(blob, Base64.NO_WRAP))
            .remove(PREF_PLAINTEXT)
            .apply()
    }

    private fun loadPrivateKeyBytes(): ByteArray {
        val mk = masterKey()
        migratePrivateKeyIfNeeded(mk)
        val enc = prefs.getString(PREF_ENC, null) ?: throw IllegalStateException("No private key")
        return try {
            KeyCrypto.decrypt(mk, Base64.decode(enc, Base64.NO_WRAP))
        } catch (e: javax.crypto.AEADBadTagException) {
            throw IllegalStateException("Private key blob corrupted or master key changed", e)
        }
    }

    private fun generateKeyPair() {
        val kpg = KeyPairGenerator.getInstance("Ed25519")
        val keyPair = kpg.generateKeyPair()
        val pubBase64 = Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP)
        val privBlob = KeyCrypto.encrypt(masterKey(), keyPair.private.encoded)
        prefs.edit()
            .putString("public_key_base64", pubBase64)
            .putString(PREF_ENC, Base64.encodeToString(privBlob, Base64.NO_WRAP))
            .apply()
    }
}
