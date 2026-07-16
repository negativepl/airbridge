package com.airbridge.service

import com.airbridge.network.PinnedTls
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HttpFileDownloaderTest {

    // Tests run over real TLS: MockWebServer serves a self-signed
    // HeldCertificate and the client pins its fingerprint via PinnedTls —
    // just like the QR-scanned pin does for the Mac's certificate in
    // production (same pattern as WebSocketClientTest).
    private val heldCertificate: HeldCertificate = HeldCertificate.Builder()
        .commonName("localhost")
        .addSubjectAlternativeName("localhost")
        .build()

    private val pin: String = PinnedTls.fingerprintOf(heldCertificate.certificate)

    private fun tlsServer(): MockWebServer = MockWebServer().apply {
        val certs = HandshakeCertificates.Builder()
            .heldCertificate(heldCertificate)
            .build()
        useHttps(certs.sslSocketFactory(), false)
    }

    @Test
    fun `successful download returns the file contents`() {
        val server = tlsServer()
        val body = "hello airbridge"
        server.enqueue(MockResponse().setBody(body))
        server.start()
        try {
            val file = HttpFileDownloader().download(
                host = server.hostName,
                port = server.port,
                certFingerprint = pin,
                transferId = "t1",
                filenameHint = "test.txt"
            ) { _, _ -> }
            assertNotNull("download should succeed", file)
            assertEquals(body, file!!.readText())
            file.delete()
        } finally {
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun `stalled stream fails within the stall timeout instead of hanging`() {
        val server = tlsServer()
        // 16 quick bytes of a 1 MB body, then 60 s of silence — a Mac that
        // stalled mid transfer.
        val stalled = MockResponse()
            .setBody(Buffer().write(ByteArray(1024 * 1024)))
            .throttleBody(16, 60, TimeUnit.SECONDS)
        server.enqueue(stalled)
        server.start()
        try {
            val start = System.nanoTime()
            val file = HttpFileDownloader(readTimeoutMs = 500).download(
                host = server.hostName,
                port = server.port,
                certFingerprint = pin,
                transferId = "t2",
                filenameHint = "stall.bin"
            ) { _, _ -> }
            val elapsedMs = (System.nanoTime() - start) / 1_000_000
            assertNull("stalled download must fail", file)
            assertTrue(
                "must fail from the read timeout (took ${elapsedMs}ms), not hang until the server gives up",
                elapsedMs < 10_000
            )
        } finally {
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun `cancelling the call aborts an in-flight download`() {
        val server = tlsServer()
        // A large body dripping slowly so the download is guaranteed to be
        // in flight when the cancel lands.
        val slow = MockResponse()
            .setBody(Buffer().write(ByteArray(1024 * 1024)))
            .throttleBody(1024, 250, TimeUnit.MILLISECONDS)
        server.enqueue(slow)
        server.start()
        try {
            val callRef = AtomicReference<okhttp3.Call>()
            val callCreated = CountDownLatch(1)
            val canceller = thread {
                callCreated.await(5, TimeUnit.SECONDS)
                Thread.sleep(300)
                callRef.get()?.cancel()
            }
            val file = HttpFileDownloader(readTimeoutMs = 30_000).download(
                host = server.hostName,
                port = server.port,
                certFingerprint = pin,
                transferId = "t3",
                filenameHint = "cancel.bin",
                onCallCreated = { callRef.set(it); callCreated.countDown() }
            ) { _, _ -> }
            canceller.join(5_000)
            assertNull("cancelled download must fail", file)
        } finally {
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun `checksum mismatch rejects the downloaded file`() {
        val server = tlsServer()
        server.enqueue(
            MockResponse()
                .setBody("corrupted payload")
                .setHeader("X-Checksum-SHA256", "00".repeat(32))
        )
        server.start()
        try {
            val file = HttpFileDownloader().download(
                host = server.hostName,
                port = server.port,
                certFingerprint = pin,
                transferId = "t4",
                filenameHint = "bad.bin"
            ) { _, _ -> }
            assertNull("checksum mismatch must fail the download", file)
        } finally {
            runCatching { server.shutdown() }
        }
    }
}
