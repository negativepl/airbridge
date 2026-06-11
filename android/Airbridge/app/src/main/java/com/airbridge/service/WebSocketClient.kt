package com.airbridge.service

import android.util.Log
import com.airbridge.protocol.Message
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.concurrent.TimeUnit

class WebSocketClient {

    companion object {
        private const val TAG = "WebSocketClient"
        private const val PING_INTERVAL_SECONDS = 15L
    }

    var onMessage: ((Message) -> Unit)? = null
    var onConnected: (() -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null

    /**
     * Invoked when reconnecting to the cached host has failed enough times that
     * the host is presumed stale (e.g. the peer moved to another network).
     * The service should re-run discovery to find the peer's new address.
     */
    var onReconnectExhausted: (() -> Unit)? = null

    private val reconnectPolicy = ReconnectPolicy()

    var isConnected: Boolean = false
        private set

    private var webSocket: WebSocket? = null
    private var currentHost: String? = null
    private var currentPort: Int = 0
    var shouldReconnect: Boolean = true

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val httpClient = OkHttpClient.Builder()
        .pingInterval(PING_INTERVAL_SECONDS, TimeUnit.SECONDS)
        .build()

    private val listener = object : WebSocketListener() {
        // Listener jest wspólny dla kolejnych socketów. Eventy z socketa innego
        // niż aktualny (zombie po reconnect/zmianie sieci) MUSZĄ być ignorowane:
        // zombie dublował każdą wiadomość (drugi upload pliku, popover) i
        // nadpisywał isConnected świeżemu połączeniu.
        private fun isCurrent(webSocket: WebSocket): Boolean =
            webSocket === this@WebSocketClient.webSocket

        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (!isCurrent(webSocket)) return
            Log.d(TAG, "WebSocket connected")
            isConnected = true
            reconnectPolicy.onSuccess()
            onConnected?.invoke()
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (!isCurrent(webSocket)) return
            try {
                val message = Message.fromJson(text)
                if (message is Message.Ping) {
                    val pong = Message.Pong(timestamp = message.timestamp)
                    webSocket.send(pong.toJson())
                } else {
                    onMessage?.invoke(message)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse message: $text", e)
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            webSocket.close(code, reason)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (!isCurrent(webSocket)) return
            Log.d(TAG, "WebSocket closed: $code $reason")
            handleDisconnect()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (!isCurrent(webSocket)) return
            Log.e(TAG, "WebSocket failure", t)
            handleDisconnect()
        }
    }

    private fun handleDisconnect() {
        // The socket is dead — clear the reference so connect() can tell a
        // live/opening socket apart from a defunct one.
        webSocket = null
        isConnected = false
        onDisconnected?.invoke()
        if (!shouldReconnect) return
        when (val decision = reconnectPolicy.onFailure()) {
            is ReconnectDecision.Retry -> scheduleReconnect(decision.delayMs)
            ReconnectDecision.Rediscover -> {
                Log.d(TAG, "Reconnect exhausted for cached host — requesting re-discovery")
                reconnectPolicy.onSuccess() // reset for the next host
                currentHost = null
                onReconnectExhausted?.invoke()
            }
        }
    }

    private fun scheduleReconnect(delayMs: Long) {
        val host = currentHost ?: return
        val port = currentPort
        scope.launch {
            delay(delayMs)
            if (shouldReconnect && !isConnected && currentHost == host) {
                Log.d(TAG, "Attempting reconnect to $host:$port (delay ${delayMs}ms)")
                connect(host, port)
            }
        }
    }

    /**
     * Forget the cached host so pending/future reconnect attempts stop targeting
     * a stale address. Closes any live socket. Discovery must supply a new host.
     */
    fun forgetHost() {
        currentHost = null
        reconnectPolicy.onSuccess()
        webSocket?.cancel()
        webSocket = null
        isConnected = false
    }

    fun connect(host: String, port: Int) {
        // Guard: discovery i reconnect potrafią zawołać connect() niemal
        // równocześnie (np. po zmianie sieci). Drugi connect do tego samego
        // hosta:portu, gdy socket żyje albo właśnie się otwiera, jest zbędny.
        val existing = webSocket
        if (existing != null && host == currentHost && port == currentPort) {
            val state = if (isConnected) "already connected" else "connection attempt in progress"
            Log.d(TAG, "connect($host:$port) ignored — $state")
            return
        }
        // Nigdy nie trzymamy dwóch socketów naraz — Mac broadcastuje do
        // wszystkich swoich połączeń, więc zombie = każda wiadomość 2x.
        existing?.cancel()
        currentHost = host
        currentPort = port
        val request = Request.Builder()
            .url("ws://$host:$port")
            .build()
        webSocket = httpClient.newWebSocket(request, listener)
    }

    fun disconnect() {
        shouldReconnect = false
        webSocket?.close(1000, "Client disconnecting")
        webSocket = null
        isConnected = false
    }

    fun send(message: Message) {
        if (isConnected) {
            webSocket?.send(message.toJson())
        } else {
            Log.w(TAG, "Cannot send message: not connected")
        }
    }

    fun sendBinary(data: ByteString) {
        if (isConnected) {
            webSocket?.send(data)
        } else {
            Log.w(TAG, "Cannot send binary: not connected")
        }
    }
}
