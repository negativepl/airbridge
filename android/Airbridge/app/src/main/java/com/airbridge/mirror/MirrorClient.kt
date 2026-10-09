package com.airbridge.mirror

import android.util.Log
import com.airbridge.network.PinnedTls
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.util.concurrent.TimeUnit

class MirrorClient(
    private val onTap: (Float, Float) -> Unit,
    private val host: String,
    private val port: Int,
    private val certFingerprint: String,
    private val pairingToken: ByteArray,
    private val screenWidth: UInt,
    private val screenHeight: UInt,
    private val orientation: UByte,
    private val onAck: (MirrorMessage.HelloAck) -> Unit,
    private val onDisconnect: () -> Unit
) {
    private val http = PinnedTls.apply(
        OkHttpClient.Builder()
            .pingInterval(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS),
        certFingerprint
    ).build()
    private var webSocket: WebSocket? = null

    fun connect() {
        val req = Request.Builder().url("wss://${com.airbridge.service.WebSocketClient.formatUrlHost(host)}:$port/").build()
        webSocket = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                val hello = MirrorMessage.Hello(pairingToken, screenWidth, screenHeight, orientation)
                webSocket.send(hello.encode().toByteString())
            }
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                runCatching { MirrorMessage.decode(bytes.toByteArray()) }
                    .onSuccess { msg ->
                        when (msg) {
                            is MirrorMessage.HelloAck -> onAck(msg)
                            is MirrorMessage.InputTap -> onTap(msg.xNorm, msg.yNorm)
                            else -> Unit
                        }
                    }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.w(TAG, "closed code=$code reason=$reason queued=${webSocket.queueSize()}")
                onDisconnect()
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w(TAG, "failure: ${t.javaClass.simpleName}: ${t.message} queued=${webSocket.queueSize()}")
                onDisconnect()
            }
        })
    }

    /**
     * Video frames are dropped while the socket's outgoing queue is backed up:
     * OkHttp closes the WebSocket once it holds 16 MiB, so an encoder that
     * outruns the link would otherwise end the session instead of skipping frames.
     */
    fun send(message: MirrorMessage) {
        val ws = webSocket ?: return
        if (message is MirrorMessage.VideoFrame && ws.queueSize() > MAX_QUEUED_BYTES) {
            dropped++
            if (dropped == 1L || dropped % 60 == 0L) Log.w(TAG, "dropping frame, queued=${ws.queueSize()} dropped=$dropped")
            return
        }
        ws.send(message.encode().toByteString())
    }
    private var dropped = 0L

    private companion object {
        const val TAG = "MirrorClient"
        const val MAX_QUEUED_BYTES = 2L * 1024 * 1024
    }

    fun close() {
        webSocket?.close(1000, "client stop")
        webSocket = null
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }
}
