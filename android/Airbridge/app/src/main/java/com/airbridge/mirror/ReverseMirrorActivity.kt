package com.airbridge.mirror

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout

/**
 * Reverse mirror viewer: shows the Mac's screen on the phone. Display-only for
 * now — connects to the Mac mirror server, sends ReverseHello, decodes the
 * incoming H.264 onto a [SurfaceView] that is letterboxed to the Mac's aspect
 * ratio (the Mac screen and the phone screen have different shapes).
 */
class ReverseMirrorActivity : Activity(), SurfaceHolder.Callback {

    private var client: ReverseMirrorClient? = null
    private var decoder: ScreenDecoder? = null

    private lateinit var container: FrameLayout
    private lateinit var surfaceView: SurfaceView

    private var host: String = ""
    private var port: Int = 0
    private var token: ByteArray = ByteArray(0)
    private var mode: Int = 0

    private var videoW = 0
    private var videoH = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = intent.getStringExtra(EXTRA_HOST) ?: return finish()
        port = intent.getIntExtra(EXTRA_PORT, 0)
        token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return finish()
        mode = intent.getIntExtra(EXTRA_MODE, 0)
        if (port == 0) return finish()

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // The container is black (letterbox bars); the SurfaceView stays
        // transparent so the video layer below shows through.
        container = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this).apply { holder.addCallback(this@ReverseMirrorActivity) }
        container.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )
        setContentView(container)
        container.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        val dec = ScreenDecoder(
            surface = holder.surface,
            onVideoSize = { w, h -> runOnUiThread { videoW = w; videoH = h; applyAspect() } }
        )
        decoder = dec
        val (sw, sh) = realDisplaySize()
        client = ReverseMirrorClient(
            host = host, port = port, pairingToken = token,
            screenWidth = sw.toUInt(), screenHeight = sh.toUInt(), mode = mode.toUByte(),
            onConfig = { sps, pps -> dec.onConfig(sps, pps) },
            onConfigHEVC = { vps, sps, pps -> dec.onConfigHEVC(vps, sps, pps) },
            onFrame = { annexB, pts -> dec.onFrame(annexB, pts) },
            onDisconnect = { runOnUiThread { finish() } }
        ).also { it.connect() }
    }

    @Suppress("DEPRECATION")
    private fun realDisplaySize(): Pair<Int, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
        val m = android.util.DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
        return m.widthPixels to m.heightPixels
    }

    /** Size the SurfaceView to fit the video's aspect ratio inside the screen (letterbox). */
    private fun applyAspect() {
        if (videoW <= 0 || videoH <= 0) return
        val cw = container.width
        val ch = container.height
        if (cw <= 0 || ch <= 0) { container.post { applyAspect() }; return }
        val scale = minOf(cw.toFloat() / videoW, ch.toFloat() / videoH)
        val w = (videoW * scale).toInt()
        val h = (videoH * scale).toInt()
        surfaceView.layoutParams = FrameLayout.LayoutParams(w, h, Gravity.CENTER)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
    override fun surfaceDestroyed(holder: SurfaceHolder) { teardown() }

    override fun onDestroy() { teardown(); super.onDestroy() }

    private fun teardown() {
        client?.close(); client = null
        decoder?.stop(); decoder = null
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_MODE = "mode"
    }
}
