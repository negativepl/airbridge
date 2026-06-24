package com.airbridge.mirror

import com.airbridge.network.PinnedTls
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
    private val certFingerprint: String,
    private val pairingToken: ByteArray,
    private val screenWidth: UInt,
    private val screenHeight: UInt,
    private val mode: UByte,
    private val onConfig: (sps: ByteArray, pps: ByteArray) -> Unit,
    private val onConfigHEVC: (vps: ByteArray, sps: ByteArray, pps: ByteArray) -> Unit,
    private val onFrame: (annexB: ByteArray, ptsUs: Long) -> Unit,
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
        val req = Request.Builder().url("wss://$host:$port/").build()
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
            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                android.util.Log.w("ReverseMirror", "onClosed code=$code reason=$reason")
                onDisconnect()
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                android.util.Log.w("ReverseMirror", "onFailure: ${t.javaClass.simpleName}: ${t.message} resp=${response?.code}")
                onDisconnect()
            }
        })
    }

    fun sendInput(type: UByte, xNorm: Float, yNorm: Float) {
        webSocket?.send(MirrorMessage.ReverseInput(type, xNorm, yNorm).encode().toByteString())
    }

    fun sendScroll(deltaX: Float, deltaY: Float) {
        webSocket?.send(MirrorMessage.ReverseScroll(deltaX, deltaY).encode().toByteString())
    }

    fun sendText(text: String) {
        webSocket?.send(MirrorMessage.ReverseText(text).encode().toByteString())
    }

    fun sendKey(code: UShort, modifiers: UByte = 0u) {
        webSocket?.send(MirrorMessage.ReverseKey(code, modifiers).encode().toByteString())
    }

    fun close() {
        webSocket?.close(1000, "reverse stop")
        webSocket = null
        http.dispatcher.executorService.shutdown()
        http.connectionPool.evictAll()
    }
}
