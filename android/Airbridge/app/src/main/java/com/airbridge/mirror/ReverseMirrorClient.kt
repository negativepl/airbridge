package com.airbridge.mirror

import com.airbridge.network.PinnedTls
import java.net.InetAddress
import java.net.Socket
import javax.net.SocketFactory
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
            .socketFactory(NoDelaySocketFactory)
            .pingInterval(15, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS),
        certFingerprint
    ).build()
    private var webSocket: WebSocket? = null
    private val arrivalGaps = GapStats("ReverseMirror", "arrival")

    fun connect() {
        val req = Request.Builder().url("wss://${com.airbridge.service.WebSocketClient.formatUrlHost(host)}:$port/").build()
        webSocket = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send(MirrorMessage.ReverseHello(pairingToken, screenWidth, screenHeight, mode).encode().toByteString())
            }
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                runCatching { MirrorMessage.decode(bytes.toByteArray()) }
                    .onSuccess { msg ->
                        when (msg) {
                            is MirrorMessage.VideoConfig -> onConfig(msg.sps, msg.pps)
                            is MirrorMessage.VideoConfigHEVC -> onConfigHEVC(msg.vps, msg.sps, msg.pps)
                            is MirrorMessage.VideoFrame -> { arrivalGaps.record(); onFrame(msg.naluBytes, msg.presentationTimestampUs.toLong()) }
                            else -> Unit
                        }
                    }
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                android.util.Log.w("ReverseMirror", "onClosed code=$code reason=$reason")
                onDisconnect()
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
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

/**
 * Plain sockets with Nagle's algorithm off. Input events to the Mac are a few
 * bytes each; buffered behind an ACK they would reach the cursor late.
 */
private object NoDelaySocketFactory : SocketFactory() {
    private val delegate: SocketFactory = SocketFactory.getDefault()
    private fun Socket.noDelay(): Socket = apply { tcpNoDelay = true }
    override fun createSocket(): Socket = delegate.createSocket().noDelay()
    override fun createSocket(host: String, port: Int): Socket = delegate.createSocket(host, port).noDelay()
    override fun createSocket(host: String, port: Int, localHost: InetAddress, localPort: Int): Socket =
        delegate.createSocket(host, port, localHost, localPort).noDelay()
    override fun createSocket(host: InetAddress, port: Int): Socket = delegate.createSocket(host, port).noDelay()
    override fun createSocket(address: InetAddress, port: Int, localAddress: InetAddress, localPort: Int): Socket =
        delegate.createSocket(address, port, localAddress, localPort).noDelay()
}

/**
 * Inter-arrival statistics for one stage of the pipeline, logged every 300
 * events: the largest gap and how many gaps exceeded 50 ms (a stall at 60 fps).
 */
internal class GapStats(private val tag: String, private val stage: String) {
    private var last = 0L
    private var maxGapMs = 0.0
    private var stalls = 0
    private var count = 0

    @Synchronized
    fun record() {
        val now = System.nanoTime()
        if (last != 0L) {
            val gap = (now - last) / 1_000_000.0
            count++
            if (gap > maxGapMs) maxGapMs = gap
            if (gap > 50) stalls++
            if (count == 300) {
                android.util.Log.d(tag, "$stage: gaps=$count maxGap=${"%.0f".format(maxGapMs)}ms stalls>50ms=$stalls")
                count = 0; maxGapMs = 0.0; stalls = 0
            }
        }
        last = now
    }
}
