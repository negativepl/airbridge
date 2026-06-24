package com.airbridge.mirror

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
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
    private var certFingerprint: String = ""

    private var videoW = 0
    private var videoH = 0

    private val handler = Handler(Looper.getMainLooper())

    private lateinit var keyboardInput: EditText
    private var keyboardVisible = false
    private var updatingText = false
    private val kbSentinel = "\u200B"   // zero-width sentinel so backspace is always detectable

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = intent.getStringExtra(EXTRA_HOST) ?: return finish()
        port = intent.getIntExtra(EXTRA_PORT, 0)
        token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return finish()
        mode = intent.getIntExtra(EXTRA_MODE, 0)
        certFingerprint = intent.getStringExtra(EXTRA_CERT_FINGERPRINT) ?: ""
        if (port == 0) return finish()

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // The container is black (letterbox bars); the SurfaceView stays
        // transparent so the video layer below shows through.
        container = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this).apply { holder.addCallback(this@ReverseMirrorActivity) }
        attachTouchControl(surfaceView)
        container.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )
        setContentView(container)
        // Re-fit the video whenever the container's size actually changes (rotation,
        // window resize). Doing it here — not in onConfigurationChanged — guarantees
        // we read the NEW dimensions; posting after a config change races the relayout
        // and re-fits against the stale (pre-rotation) size, leaving the image cropped.
        container.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if ((right - left) != (oldRight - oldLeft) || (bottom - top) != (oldBottom - oldTop)) {
                applyAspect()
            }
        }
        setupKeyboard()
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
            host = host, port = port, certFingerprint = certFingerprint, pairingToken = token,
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

    // MARK: - Keyboard

    private fun setupKeyboard() {
        // Hidden field that captures soft-keyboard input and forwards it. Visible-
        // password input type disables autocorrect/composing so keys commit one
        // at a time. A zero-width kbSentinel makes backspace-on-empty detectable.
        keyboardInput = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            setText(kbSentinel); setSelection(text.length)
            alpha = 0f
            isCursorVisible = false
        }
        container.addView(keyboardInput, FrameLayout.LayoutParams(1, 1, Gravity.TOP or Gravity.START))

        keyboardInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (updatingText) return
                val cur = keyboardInput.text?.toString() ?: ""
                client?.let { c ->
                    if (cur.length > kbSentinel.length) {
                        val inserted = cur.substring(kbSentinel.length)
                        if (inserted == "\n") c.sendKey(2u) else c.sendText(inserted)
                    } else if (cur.isEmpty()) {
                        c.sendKey(1u)   // backspace
                    }
                }
                updatingText = true
                keyboardInput.setText(kbSentinel)
                keyboardInput.setSelection(kbSentinel.length)
                updatingText = false
            }
        })

        keyboardInput.setOnKeyListener { _, keyCode, event ->
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
            val c = client ?: return@setOnKeyListener false
            when (keyCode) {
                KeyEvent.KEYCODE_ENTER -> { c.sendKey(2u); true }
                KeyEvent.KEYCODE_TAB -> { c.sendKey(3u); true }
                KeyEvent.KEYCODE_ESCAPE -> { c.sendKey(4u); true }
                KeyEvent.KEYCODE_DPAD_LEFT -> { c.sendKey(5u); true }
                KeyEvent.KEYCODE_DPAD_RIGHT -> { c.sendKey(6u); true }
                KeyEvent.KEYCODE_DPAD_UP -> { c.sendKey(7u); true }
                KeyEvent.KEYCODE_DPAD_DOWN -> { c.sendKey(8u); true }
                else -> false   // DEL falls through to the TextWatcher
            }
        }

        fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()
        val toggle = Button(this).apply {
            text = "⌨"
            setOnClickListener { toggleKeyboard() }
        }
        container.addView(toggle, FrameLayout.LayoutParams(dp(52), dp(52), Gravity.BOTTOM or Gravity.END).apply {
            rightMargin = dp(16); bottomMargin = dp(16)
        })
    }

    private fun toggleKeyboard() {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        keyboardVisible = if (keyboardVisible) {
            imm.hideSoftInputFromWindow(keyboardInput.windowToken, 0); false
        } else {
            keyboardInput.requestFocus()
            imm.showSoftInput(keyboardInput, InputMethodManager.SHOW_IMPLICIT); true
        }
    }

    // Touch -> reverse control. Single finger: tap = click, drag = press+drag.
    // Two fingers: scroll. The SurfaceView is already sized to the video rect,
    // so coords map 1:1 to the captured display.
    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouchControl(view: SurfaceView) {
        var pressed = false       // left button held (drag in progress)
        var scrolling = false     // two-finger scroll
        var consumed = false      // long-press right-click fired; suppress the click
        var downX = 0f            // normalized down point
        var downY = 0f
        var rawDownX = 0f         // pixel down point (move threshold)
        var rawDownY = 0f
        var anchorX = 0f          // pixel scroll anchor
        var anchorY = 0f
        val moveSlop = 28f
        val longPress = Runnable {
            if (!pressed && !scrolling && !consumed) {
                consumed = true
                client?.sendInput(4u, downX, downY)   // right-click
            }
        }
        view.setOnTouchListener { v, e ->
            val w = v.width.toFloat(); val h = v.height.toFloat()
            val c = client
            if (w <= 0f || h <= 0f || c == null) return@setOnTouchListener true
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    pressed = false; scrolling = false; consumed = false
                    downX = (e.x / w).coerceIn(0f, 1f); downY = (e.y / h).coerceIn(0f, 1f)
                    rawDownX = e.x; rawDownY = e.y
                    handler.postDelayed(longPress, 420)
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    if (e.pointerCount >= 2) {
                        handler.removeCallbacks(longPress)
                        if (pressed) { c.sendInput(2u, downX, downY); pressed = false }  // release nascent drag
                        scrolling = true
                        anchorX = (e.getX(0) + e.getX(1)) / 2
                        anchorY = (e.getY(0) + e.getY(1)) / 2
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    if (scrolling && e.pointerCount >= 2) {
                        val cx = (e.getX(0) + e.getX(1)) / 2
                        val cy = (e.getY(0) + e.getY(1)) / 2
                        c.sendScroll(cx - anchorX, cy - anchorY)
                        anchorX = cx; anchorY = cy
                    } else if (!scrolling && !consumed) {
                        val moved = kotlin.math.hypot(e.x - rawDownX, e.y - rawDownY) > moveSlop
                        if (pressed || moved) {
                            if (!pressed) { handler.removeCallbacks(longPress); c.sendInput(1u, downX, downY); pressed = true }
                            c.sendInput(3u, (e.x / w).coerceIn(0f, 1f), (e.y / h).coerceIn(0f, 1f))  // drag
                        }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPress)
                    if (!scrolling && !consumed) {
                        if (!pressed) {
                            c.sendInput(1u, downX, downY); c.sendInput(2u, downX, downY)  // tap = click
                        } else {
                            c.sendInput(2u, (e.x / w).coerceIn(0f, 1f), (e.y / h).coerceIn(0f, 1f))  // release drag
                        }
                    }
                    pressed = false; scrolling = false; consumed = false
                }
            }
            true
        }
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
        const val EXTRA_CERT_FINGERPRINT = "certFingerprint"
    }
}
