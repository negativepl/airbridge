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
        private const val RECONNECT_DELAY_MS = 3000L
        private const val PING_INTERVAL_SECONDS = 15L
    }

    var onMessage: ((Message) -> Unit)? = null
    var onConnected: (() -> Unit)? = null
    var onDisconnected: (() -> Unit)? = null

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
        override fun onOpen(webSocket: WebSocket, response: Response) {
            Log.d(TAG, "WebSocket connected")
            isConnected = true
            onConnected?.invoke()
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
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
            Log.d(TAG, "WebSocket closed: $code $reason")
            handleDisconnect()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "WebSocket failure", t)
            handleDisconnect()
        }
    }

    private fun handleDisconnect() {
        isConnected = false
        onDisconnected?.invoke()
        if (shouldReconnect) {
            scheduleReconnect()
        }
    }

    private fun scheduleReconnect() {
        val host = currentHost ?: return
        val port = currentPort
        scope.launch {
            delay(RECONNECT_DELAY_MS)
            if (shouldReconnect && !isConnected) {
                Log.d(TAG, "Attempting reconnect to $host:$port")
                connect(host, port)
            }
        }
    }

    fun connect(host: String, port: Int) {
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
