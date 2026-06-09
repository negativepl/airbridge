package com.airbridge.service

import com.airbridge.protocol.ContentType
import com.airbridge.protocol.Message
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WebSocketClientTest {

    /** Serwerowy listener zbierający otwarte sockety i sygnalizujący zamknięcia. */
    private class ServerSocketRecorder : WebSocketListener() {
        val opened = CountDownLatch(1)
        val closed = CountDownLatch(1)
        @Volatile var socket: WebSocket? = null

        override fun onOpen(webSocket: WebSocket, response: Response) {
            socket = webSocket
            opened.countDown()
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            closed.countDown()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            closed.countDown()
        }
    }

    @Test
    fun `connect while already connected cancels the previous socket`() {
        val server = MockWebServer()
        val first = ServerSocketRecorder()
        val second = ServerSocketRecorder()
        server.enqueue(MockResponse().withWebSocketUpgrade(first))
        server.enqueue(MockResponse().withWebSocketUpgrade(second))
        server.start()

        val client = WebSocketClient()
        client.shouldReconnect = false
        try {
            client.connect(server.hostName, server.port)
            assertTrue("first socket should open", first.opened.await(5, TimeUnit.SECONDS))

            // Drugi connect (np. discovery po zmianie sieci) — stary socket musi paść.
            client.connect(server.hostName, server.port)
            assertTrue("second socket should open", second.opened.await(5, TimeUnit.SECONDS))
            assertTrue(
                "first (stale) socket should be cancelled by the second connect",
                first.closed.await(5, TimeUnit.SECONDS)
            )
        } finally {
            // Cleanup nie może maskować asercji — MockWebServer potrafi rzucić
            // przy zamykaniu, gdy zombie-socket wciąż trzyma połączenie.
            runCatching { client.disconnect() }
            runCatching { first.socket?.close(1000, null) }
            runCatching { second.socket?.close(1000, null) }
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun `message from stale socket is not delivered`() {
        val server = MockWebServer()
        val first = ServerSocketRecorder()
        val second = ServerSocketRecorder()
        server.enqueue(MockResponse().withWebSocketUpgrade(first))
        server.enqueue(MockResponse().withWebSocketUpgrade(second))
        server.start()

        val received = AtomicInteger(0)
        val gotMessage = CountDownLatch(1)
        val client = WebSocketClient()
        client.shouldReconnect = false
        client.onMessage = {
            received.incrementAndGet()
            gotMessage.countDown()
        }
        try {
            client.connect(server.hostName, server.port)
            assertTrue(first.opened.await(5, TimeUnit.SECONDS))
            client.connect(server.hostName, server.port)
            assertTrue(second.opened.await(5, TimeUnit.SECONDS))

            // Mac broadcastuje do WSZYSTKICH swoich połączeń — emulacja:
            // oba serwerowe sockety wysyłają tę samą wiadomość.
            val json = Message.Pong(timestamp = 123L).toJson()
            first.socket?.send(json)
            second.socket?.send(json)

            assertTrue("message should arrive", gotMessage.await(5, TimeUnit.SECONDS))
            // Krótka karencja na ewentualny duplikat ze stalego socketa.
            Thread.sleep(500)
            assertEquals("stale socket must not double-deliver", 1, received.get())
        } finally {
            // Cleanup nie może maskować asercji — MockWebServer potrafi rzucić
            // przy zamykaniu, gdy zombie-socket wciąż trzyma połączenie.
            runCatching { client.disconnect() }
            runCatching { first.socket?.close(1000, null) }
            runCatching { second.socket?.close(1000, null) }
            runCatching { server.shutdown() }
        }
    }

    @Test
    fun `message serialization roundtrip`() {
        val original = Message.ClipboardUpdate(
            sourceId = "device-abc",
            contentType = ContentType.PLAIN_TEXT,
            data = "Hello, Airbridge!",
            timestamp = 1712345678901L
        )

        val json = original.toJson()
        val decoded = Message.fromJson(json) as Message.ClipboardUpdate

        assertEquals(original.sourceId, decoded.sourceId)
        assertEquals(original.contentType, decoded.contentType)
        assertEquals(original.data, decoded.data)
        assertEquals(original.timestamp, decoded.timestamp)
    }

    @Test
    fun `file chunk message roundtrip`() {
        val original = Message.FileChunk(
            transferId = "transfer-xyz-123",
            chunkIndex = 42,
            data = "SGVsbG8gV29ybGQ="
        )

        val json = original.toJson()
        val decoded = Message.fromJson(json) as Message.FileChunk

        assertEquals(original.transferId, decoded.transferId)
        assertEquals(original.chunkIndex, decoded.chunkIndex)
        assertEquals(original.data, decoded.data)
    }
}
