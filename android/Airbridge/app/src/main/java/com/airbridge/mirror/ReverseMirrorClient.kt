package com.airbridge.mirror

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import java.util.concurrent.TimeUnit

/**
 * Reverse mirror (Mac -> phone) client. Opens the same mirror WebSocket the
 * forward path uses, but sends a ReverseHello and consumes the VideoConfig /
 * VideoFrame stream the Mac sends back, handing it to [onConfig] / [onFrame].
 */
class ReverseMirrorClient(
    private val host: String,
    private val port: Int,
    private val pairingToken: ByteArray,
    private val screenWidth: UInt,
    private val screenHeight: UInt,
    private val mode: UByte,
    private val onConfig: (sps: ByteArray, pps: ByteArray) -> Unit,
    private val onConfigHEVC: (vps: ByteArray, sps: ByteArray, pps: ByteArray) -> Unit,
    private val onFrame: (annexB: ByteArray, ptsUs: Long) -> Unit,
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
                ws.send(MirrorMessage.ReverseHello(pairingToken, screenWidth, screenHeight, mode).encode().toByteString())
            }
            override fun onMessage(ws: WebSocket, bytes: ByteString) {
                runCatching { MirrorMessage.decode(bytes.toByteArray()) }
                    .onSuccess { msg ->
                        when (msg) {
                            is MirrorMessage.VideoConfig -> onConfig(msg.sps, msg.pps)
                            is MirrorMessage.VideoConfigHEVC -> onConfigHEVC(msg.vps, msg.sps, msg.pps)
                            is MirrorMessage.VideoFrame -> onFrame(msg.naluBytes, msg.presentationTimestampUs.toLong())
                            else -> Unit
                        }
                    }
            }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) { onDisconnect() }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) { onDisconnect() }
        })
    }

    fun close() {
        webSocket?.close(1000, "reverse stop")
        webSocket = null
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }
}
