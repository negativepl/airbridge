package com.airbridge.update

import org.json.JSONObject
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * The update manifest published by release.sh. The signature covers the RAW
 * manifest bytes — always call [verifySignature] before [parse].
 */
data class UpdateManifest(
    val version: String,
    val versionCode: Int,
    val publishedAt: String,
    val android: Asset,
    val changelogPl: List<String>,
    val changelogEn: List<String>
) {
    data class Asset(val url: String, val sha256: String, val size: Long)

    fun isNewerThan(installedVersionCode: Int): Boolean = versionCode > installedVersionCode

    companion object {
        // Ed25519 X.509 DER prefix — same trick KeyCrypto uses for pairing keys.
        private val ED25519_X509_PREFIX = byteArrayOf(
            0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
        )

        fun parse(json: String): UpdateManifest {
            val o = JSONObject(json)
            val a = o.getJSONObject("android")
            val ch = o.getJSONObject("changelog")
            fun list(key: String): List<String> {
                val arr = ch.getJSONArray(key)
                return (0 until arr.length()).map { arr.getString(it) }
            }
            return UpdateManifest(
                version = o.getString("version"),
                versionCode = o.getInt("versionCode"),
                publishedAt = o.getString("publishedAt"),
                android = Asset(a.getString("url"), a.getString("sha256"), a.getLong("size")),
                changelogPl = list("pl"),
                changelogEn = list("en")
            )
        }

        fun verifySignature(
            manifestBytes: ByteArray,
            signatureBase64: String,
            publicKeyRawBase64: String
        ): Boolean = try {
            val raw = Base64.getDecoder().decode(publicKeyRawBase64)
            val keySpec = X509EncodedKeySpec(ED25519_X509_PREFIX + raw)
            val publicKey = KeyFactory.getInstance("Ed25519").generatePublic(keySpec)
            Signature.getInstance("Ed25519").run {
                initVerify(publicKey)
                update(manifestBytes)
                verify(Base64.getDecoder().decode(signatureBase64))
            }
        } catch (_: Exception) {
            false
        }
    }
}
