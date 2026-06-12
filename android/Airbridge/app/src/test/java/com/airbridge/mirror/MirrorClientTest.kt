package com.airbridge.mirror

import com.airbridge.network.PinnedTls
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Before
import org.junit.Test
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class MirrorClientTest {

    private lateinit var server: MockWebServer

    // Real TLS (wss) like production: MockWebServer serves a self-signed
    // certificate and the client pins its fingerprint via PinnedTls.
    private val heldCertificate: HeldCertificate = HeldCertificate.Builder()
        .commonName("localhost")
        .addSubjectAlternativeName("localhost")
        .build()

    private val pin: String = PinnedTls.fingerprintOf(heldCertificate.certificate)

    @Before fun setUp() {
        server = MockWebServer().apply {
            val certs = HandshakeCertificates.Builder()
                .heldCertificate(heldCertificate)
                .build()
            useHttps(certs.sslSocketFactory(), false)
            start()
        }
    }
    @After fun tearDown() {
        // MockWebServer's internal task-runner threads may still be draining; ignore the timeout
        try { server.shutdown() } catch (_: java.io.IOException) { }
    }

    @Test fun `sends HELLO on connect`() {
        val received = LinkedBlockingQueue<ByteString>()
        server.enqueue(MockResponse().withWebSocketUpgrade(object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                received.offer(bytes)
            }
        }))

        val token = ByteArray(16) { 0xAB.toByte() }
        val client = MirrorClient(
            host = server.hostName,
            port = server.port,
            certFingerprint = pin,
            pairingToken = token,
            screenWidth = 1080u,
            screenHeight = 2376u,
            orientation = 0u,
            onAck = {},
            onTap = { _, _ -> },
            onDisconnect = {}
        )
        client.connect()

        val firstMessage = received.poll(5, TimeUnit.SECONDS)
            ?: error("HELLO frame not received within 5s")
        val msg = MirrorMessage.decode(firstMessage.toByteArray())
        check(msg is MirrorMessage.Hello) { "Expected HELLO, got $msg" }
        assertArrayEquals(token, msg.token)

        client.close()
        // Allow WebSocket close handshake to complete before MockWebServer shuts down
        Thread.sleep(200)
    }
}
