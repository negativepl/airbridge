package com.airbridge.network

import okhttp3.OkHttpClient
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * Certificate pinning for the Mac's self-signed TLS certificate. The pin is
 * the SHA-256 hex of the certificate DER, learned from the pairing QR code —
 * that physical scan is the trust anchor, not any CA. Hostname verification is
 * disabled (we connect to raw LAN IPs); identity comes solely from the pin.
 */
object PinnedTls {

    fun fingerprintOf(cert: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(cert.encoded)
            .joinToString("") { "%02x".format(it) }

    fun trustManager(pinnedFingerprint: String): X509TrustManager =
        object : X509TrustManager {
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
                val leaf = chain?.firstOrNull()
                    ?: throw CertificateException("Empty certificate chain")
                if (pinnedFingerprint.isBlank()) {
                    throw CertificateException("No pinned certificate — device not paired over TLS")
                }
                val presented = fingerprintOf(leaf)
                if (!MessageDigest.isEqual(
                        presented.toByteArray(), pinnedFingerprint.lowercase().toByteArray())) {
                    throw CertificateException(
                        "Certificate fingerprint mismatch: expected $pinnedFingerprint, got $presented")
                }
            }

            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {
                throw CertificateException("Client certificates are not used")
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }

    /** Applies pinned TLS to an OkHttp builder; callers keep their own timeouts. */
    fun apply(builder: OkHttpClient.Builder, pinnedFingerprint: String): OkHttpClient.Builder {
        val tm = trustManager(pinnedFingerprint)
        val context = SSLContext.getInstance("TLS")
        context.init(null, arrayOf(tm), SecureRandom())
        return builder
            .sslSocketFactory(context.socketFactory, tm)
            .hostnameVerifier { _, _ -> true }
    }
}
