package com.airbridge.mirror

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
    private val pairingToken: ByteArray,
    private val screenWidth: UInt,
    private val screenHeight: UInt,
    private val orientation: UByte,
    private val onAck: (MirrorMessage.HelloAck) -> Unit,
    private val onDisconnect: () -> Unit
) {
    private val http = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build()
    private var webSocket: WebSocket? = null

    fun connect() {
        val req = Request.Builder().url("ws://$host:$port/").build()
        webSocket = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                val hello = MirrorMessage.Hello(pairingToken, screenWidth, screenHeight, orientation)
                ws.send(hello.encode().toByteString())
            }
            override fun onMessage(ws: WebSocket, bytes: ByteString) {
                runCatching { MirrorMessage.decode(bytes.toByteArray()) }
                    .onSuccess { msg ->
                        when (msg) {
                            is MirrorMessage.HelloAck -> onAck(msg)
                            is MirrorMessage.InputTap -> onTap(msg.xNorm, msg.yNorm)
                            else -> Unit
                        }
                    }
            }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) { onDisconnect() }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { onDisconnect() }
        })
    }

    fun send(message: MirrorMessage) {
        webSocket?.send(message.encode().toByteString())
    }

    fun close() {
        webSocket?.close(1000, "client stop")
        webSocket = null
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }
}
