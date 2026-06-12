package com.airbridge.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

class PinnedTlsTest {

    private val cert1Pem = """
        -----BEGIN CERTIFICATE-----
        MIIBfDCCASOgAwIBAgIUQcmS7oUNI2lcw6LT2yH/57usCrswCgYIKoZIzj0EAwIw
        FDESMBAGA1UEAwwJQWlyQnJpZGdlMB4XDTI2MDYxMjA3MDIyM1oXDTM2MDYwOTA3
        MDIyM1owFDESMBAGA1UEAwwJQWlyQnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0D
        AQcDQgAE73bimpGMpysoScU4VeW7284J9yY9Af+EBIo8juY6rpuwPh1bZuzgB72E
        nSwITIFoD6qO5FnCpZDDVJVX+rGDxKNTMFEwHQYDVR0OBBYEFAOvXG/i2bJDlJH9
        rCU6gISFUXWQMB8GA1UdIwQYMBaAFAOvXG/i2bJDlJH9rCU6gISFUXWQMA8GA1Ud
        EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIgfEGHuBiRrW9Fdlu7xZJTRQ8D
        vo3FVnEo1K5M2MovfVkCICEoGnoZwz0oKFJS8CZcwe4oVOww7+tdiXuOD2cdDBiY
        -----END CERTIFICATE-----
    """.trimIndent()
    private val cert1Fingerprint =
        "7cd93ad957b9858cbabd681a754452115a797505f27a160c38b8b71222321471"

    private val cert2Pem = """
        -----BEGIN CERTIFICATE-----
        MIIBfjCCASOgAwIBAgIUL1I4fkdey31ShkDY4xnjbtvgKWYwCgYIKoZIzj0EAwIw
        FDESMBAGA1UEAwwJQWlyQnJpZGdlMB4XDTI2MDYxMjA3MDIyM1oXDTM2MDYwOTA3
        MDIyM1owFDESMBAGA1UEAwwJQWlyQnJpZGdlMFkwEwYHKoZIzj0CAQYIKoZIzj0D
        AQcDQgAE8nF35IOvlyHNNy2H2VbWliL8eD8k/rGlmhRhxdN1MOwLxH7UjvAWiHky
        PWi1urOPrgSA7rv/9K3SrcOnQ5Po0qNTMFEwHQYDVR0OBBYEFKHDMSirBpYBWY2r
        GyA2pd1d9SztMB8GA1UdIwQYMBaAFKHDMSirBpYBWY2rGyA2pd1d9SztMA8GA1Ud
        EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAMoPfpGH6XxGUrlmkiF0yW4W
        wSNcZU8TnD65gRlWRpGsAiEA28TqlE5x95I0QziPDkFV2Nbx4xcdRhV0Lyp4Kb6r
        8A8=
        -----END CERTIFICATE-----
    """.trimIndent()

    private fun parse(pem: String): X509Certificate =
        CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(pem.toByteArray())) as X509Certificate

    @Test
    fun `fingerprint matches openssl sha256 over DER`() {
        assertEquals(cert1Fingerprint, PinnedTls.fingerprintOf(parse(cert1Pem)))
    }

    @Test
    fun `pinned cert is accepted`() {
        PinnedTls.trustManager(cert1Fingerprint)
            .checkServerTrusted(arrayOf(parse(cert1Pem)), "ECDHE_ECDSA")
    }

    @Test
    fun `different cert is rejected`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager(cert1Fingerprint)
                .checkServerTrusted(arrayOf(parse(cert2Pem)), "ECDHE_ECDSA")
        }
    }

    @Test
    fun `blank pin rejects everything`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager("")
                .checkServerTrusted(arrayOf(parse(cert1Pem)), "ECDHE_ECDSA")
        }
    }

    @Test
    fun `empty chain is rejected`() {
        assertThrows(CertificateException::class.java) {
            PinnedTls.trustManager(cert1Fingerprint)
                .checkServerTrusted(emptyArray(), "ECDHE_ECDSA")
        }
    }
}
