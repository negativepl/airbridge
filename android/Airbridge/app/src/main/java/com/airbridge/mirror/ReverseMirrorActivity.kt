package com.airbridge.mirror

import android.annotation.SuppressLint
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
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LoadingIndicator
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.airbridge.ui.AirbridgeTheme

/**
 * Reverse mirror viewer: shows the Mac's screen on the phone. Display-only for
 * now — connects to the Mac mirror server, sends ReverseHello, decodes the
 * incoming H.264 onto a [SurfaceView] that is letterboxed to the Mac's aspect
 * ratio (the Mac screen and the phone screen have different shapes).
 */
class ReverseMirrorActivity : ComponentActivity(), SurfaceHolder.Callback {

    private var client: ReverseMirrorClient? = null
    private var decoder: ScreenDecoder? = null

    private lateinit var container: FrameLayout
    private lateinit var surfaceView: SurfaceView
    private lateinit var fadeOverlay: View

    private var host: String = ""
    private var port: Int = 0
    private var token: ByteArray = ByteArray(0)
    private var mode: Int = 0
    private var certFingerprint: String = ""

    private var videoW = 0
    private var videoH = 0
    /// Soft-keyboard height; the stream is fitted into the space above it.
    private var imeHeight = 0
    /// Identifies the live stream so a superseded client's disconnect (during a
    /// rotation restart) doesn't close the activity.
    private var streamGen = 0
    private var restartOnClose = false

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
        // Black overlay above the video — fades in over the brief reconnect when
        // the virtual display is rebuilt on rotation, so the switch doesn't blink.
        // Carries the M3 Expressive morphing loader (native, on-brand) so the
        // user sees a deliberate transition rather than a glitch.
        fadeOverlay = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            alpha = 0f
            addView(
                ComposeView(this@ReverseMirrorActivity).apply {
                    setContent {
                        AirbridgeTheme(themeMode = "dark") {
                            LoadingIndicator(modifier = Modifier.size(64.dp))
                        }
                    }
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER
                )
            )
        }
        container.addView(
            fadeOverlay,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        setContentView(container)
        // Re-fit the video whenever the container's size actually changes (rotation,
        // window resize). Doing it here — not in onConfigurationChanged — guarantees
        // we read the NEW dimensions; posting after a config change races the relayout
        // and re-fits against the stale (pre-rotation) size, leaving the image cropped.
        container.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            val w = right - left; val h = bottom - top
            val ow = oldRight - oldLeft; val oh = oldBottom - oldTop
            if (w == ow && h == oh) return@addOnLayoutChangeListener   // no size change
            // Mode 1 rebuilds the virtual display when the screen's aspect ratio
            // changes meaningfully (rotation OR fold/unfold); mode 0 and minor
            // resizes just re-fit the existing video. ow/oh == 0 on first layout.
            if (mode == 1 && ow > 0 && oh > 0 &&
                kotlin.math.abs(w.toFloat() / h - ow.toFloat() / oh) > 0.1f) {
                restartStreamForRotation()
            } else {
                applyAspect()
            }
        }
        // Track the soft keyboard height so the stream can fit into the space
        // above it instead of being covered — there is plenty of black letterbox
        // room in portrait. Re-fit whenever the IME inset changes.
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            if (ime != imeHeight) { imeHeight = ime; applyAspect() }
            insets
        }
        setupKeyboard()
        // Immersive fullscreen via the modern API (the legacy SYSTEM_UI_FLAG_*
        // bitmask is deprecated since API 30). Bars stay hidden, swipe reveals
        // them transiently.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, container).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) { startStream() }

    private fun startStream() {
        val gen = ++streamGen
        val dec = ScreenDecoder(
            surface = surfaceView.holder.surface,
            onVideoSize = { w, h ->
                runOnUiThread {
                    videoW = w; videoH = h; applyAspect()
                    // Reveal the (possibly reshaped) video; start delay lets the
                    // first frame land before the fade uncovers it.
                    fadeOverlay.animate().alpha(0f).setStartDelay(90).setDuration(240).start()
                }
            }
        )
        decoder = dec
        val (sw, sh) = realDisplaySize()
        client = ReverseMirrorClient(
            host = host, port = port, certFingerprint = certFingerprint, pairingToken = token,
            screenWidth = sw.toUInt(), screenHeight = sh.toUInt(), mode = mode.toUByte(),
            onConfig = { sps, pps -> dec.onConfig(sps, pps) },
            onConfigHEVC = { vps, sps, pps -> dec.onConfigHEVC(vps, sps, pps) },
            onFrame = { annexB, pts -> dec.onFrame(annexB, pts) },
            onDisconnect = { runOnUiThread { onClientGone(gen) } }
        ).also { it.connect() }
    }

    private fun onClientGone(gen: Int) {
        if (gen != streamGen) return            // superseded client (rotation restart) — ignore
        if (restartOnClose) {
            restartOnClose = false
            decoder?.stop(); decoder = null
            startStream()                        // reconnect with the new dimensions
        } else {
            finish()
        }
    }

    /**
     * Mode 1 (virtual second display): on rotation the Mac must rebuild the
     * virtual screen in the new orientation (it can't resize in place).
     * Reconnect with the new dimensions — but only AFTER the old connection is
     * fully closed, because the Mac ignores a new hello while a pipeline still
     * exists, and tears the old display down on disconnect.
     */
    private fun restartStreamForRotation() {
        val c = client ?: return
        // Fade to black to hide the reconnect; the new stream fades it back in.
        fadeOverlay.animate().alpha(1f).setStartDelay(0).setDuration(140).start()
        client = null
        restartOnClose = true
        c.close()   // → onClientGone(currentGen) → startStream()
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
        val fullH = container.height
        if (cw <= 0 || fullH <= 0) { container.post { applyAspect() }; return }
        // Fit into the area ABOVE the keyboard; when no keyboard, that's the full
        // height, so this stays centered as before.
        val usableH = (fullH - imeHeight).coerceAtLeast(1)
        val scale = minOf(cw.toFloat() / videoW, usableH.toFloat() / videoH)
        val w = (videoW * scale).toInt()
        val h = (videoH * scale).toInt()
        surfaceView.layoutParams = FrameLayout.LayoutParams(w, h, Gravity.TOP or Gravity.CENTER_HORIZONTAL).also {
            it.topMargin = ((usableH - h) / 2).coerceAtLeast(0)
        }
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
        val controller = WindowInsetsControllerCompat(window, keyboardInput)
        keyboardVisible = if (keyboardVisible) {
            controller.hide(WindowInsetsCompat.Type.ime()); false
        } else {
            keyboardInput.requestFocus()
            controller.show(WindowInsetsCompat.Type.ime()); true
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
