package com.airbridge.security

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.UUID

class KeyManager(context: Context) {

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

    fun getPublicKeyFingerprint(): String {
        val rawBytes = getRawPublicKeyBytes()
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(rawBytes)
        return hash.joinToString("") { "%02x".format(it) }
    }

    fun sign(data: ByteArray): String {
        val privKeyBase64 = prefs.getString("private_key_base64", null)
            ?: throw IllegalStateException("No private key")
        val privKeyBytes = Base64.decode(privKeyBase64, Base64.NO_WRAP)
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

    private fun generateKeyPair() {
        val kpg = KeyPairGenerator.getInstance("Ed25519")
        val keyPair = kpg.generateKeyPair()
        val pubBase64 = Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP)
        val privBase64 = Base64.encodeToString(keyPair.private.encoded, Base64.NO_WRAP)
        prefs.edit()
            .putString("public_key_base64", pubBase64)
            .putString("private_key_base64", privBase64)
            .apply()
    }
}
