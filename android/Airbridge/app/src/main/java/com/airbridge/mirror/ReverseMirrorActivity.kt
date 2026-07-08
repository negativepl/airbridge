package com.airbridge.mirror

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.graphics.SurfaceTexture
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.EditText
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.Mouse
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.airbridge.ui.AirbridgeTheme

/**
 * Reverse mirror viewer: shows the Mac's screen on the phone. Display-only for
 * now — connects to the Mac mirror server, sends ReverseHello, decodes the
 * incoming H.264 onto a [TextureView] that is letterboxed to the Mac's aspect
 * ratio (the Mac screen and the phone screen have different shapes).
 */
class ReverseMirrorActivity : ComponentActivity(), TextureView.SurfaceTextureListener {

    private var client: ReverseMirrorClient? = null
    private var decoder: ScreenDecoder? = null

    private lateinit var container: FrameLayout
    // TextureView (not SurfaceView) so the magnifier zoom/pan scales the video
    // smoothly in the view hierarchy without the SurfaceView compositor smear.
    private lateinit var textureView: TextureView
    private var videoSurface: Surface? = null
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

    private lateinit var keyboardInput: EditText
    private var keyboardVisible = false
    private var updatingText = false
    private val kbSentinel = "\u200B"   // zero-width sentinel so backspace is always detectable

    // MARK: - Trackpad (relative pointer) panel
    /// When true, the bottom trackpad panel is open: finger deltas move a virtual
    /// cursor (like a Mac trackpad) instead of the default absolute touch-on-video.
    /// Mutually exclusive with the soft keyboard.
    private var trackpadMode = false
    /// Virtual cursor position in normalized 0..1, driven relatively.
    private var cursorX = 0.5f
    private var cursorY = 0.5f
    private lateinit var trackpadPad: FrameLayout          // the trackpad panel surface
    private var toggleRow: View? = null
    private val trackpadActive = androidx.compose.runtime.mutableStateOf(false)
    private val keyboardActive = androidx.compose.runtime.mutableStateOf(false)

    // MARK: - Screen-layer zoom (local magnifier; sends nothing to the Mac)
    private var zoomScale = 1f
    private var zoomPanX = 0f
    private var zoomPanY = 0f
    private var fitScale = 1f           // extra downscale so the video fits above a panel
    private var fitPanY = 0f            // vertical pan to centre it in the free area
    private var zoomReveal: ValueAnimator? = null
    private var videoRevealed = false   // reveal animation runs once per stream, not per frame
    private val zoomPanGain = 2.6f      // one-finger pan speed over the magnified image
    private lateinit var scaleDetector: ScaleGestureDetector
    private lateinit var gestureDetector: GestureDetector
    /// Last observed soft-keyboard height, so the trackpad panel can match it exactly.
    private var lastImeHeight = 0
    private var panelTarget = 0                            // trackpad panel full height
    private var panelReserved = 0f                         // animated bottom space it reserves (0..target)
    private var panelAnimator: ValueAnimator? = null
    private var hidePanelAfterKeyboard = false             // drop the pad once the keyboard has fully risen
    private var imeAnimating = false                        // keyboard is mid-slide; onProgress owns the fit
    private val trackpadPanelFraction = 0.45f              // fallback height before the keyboard is ever seen
    // Relative-motion feel: base gain plus a speed-based acceleration multiplier so
    // slow drags are precise (~1:1) while fast flicks travel farther.
    private val trackpadGain = 1.6f
    private val trackpadAccelK = 0.08f
    private val trackpadAccelMax = 3.0f
    private val trackpadScrollGain = 2.6f   // two-finger scroll felt too slow at 1:1

    private fun dp(v: Int) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = intent.getStringExtra(EXTRA_HOST) ?: return finish()
        port = intent.getIntExtra(EXTRA_PORT, 0)
        token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return finish()
        mode = intent.getIntExtra(EXTRA_MODE, 0)
        certFingerprint = intent.getStringExtra(EXTRA_CERT_FINGERPRINT) ?: ""
        if (port == 0) return finish()

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // The container is black (letterbox bars); the TextureView renders the video.
        container = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        textureView = TextureView(this).apply {
            isOpaque = true   // the view is sized to the video rect; opaque avoids stale-buffer ghosting
            surfaceTextureListener = this@ReverseMirrorActivity
        }
        attachZoomControl(textureView)
        container.addView(
            textureView,
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
            alpha = 1f   // mask the connect with the loader until the first frame lands
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

        // Trackpad panel: a large surface docked at the bottom, like the soft
        // keyboard and mutually exclusive with it. Whole surface behaves as a Mac
        // trackpad (one finger = left, two fingers = right, two-finger drag =
        // scroll). Absolute touch-on-video above still works. Hidden until ▭.
        trackpadPad = FrameLayout(this).apply {
            background = trackpadPanelBackground()
            visibility = View.GONE
        }
        attachTrackpadControl(trackpadPad)
        addTrackpadMarkings(trackpadPad)
        container.addView(
            trackpadPad,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, 0, Gravity.BOTTOM)
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
        // Track the soft keyboard height. CRUCIAL: while the IME is animating we do
        // NOT re-fit from this listener — it reports the FINAL height up front, which
        // would snap the video to its end position for one frame before the animation
        // catches up. During the animation only onProgress (below) drives the fit.
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            imeHeight = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
            if (imeHeight > dp(100)) lastImeHeight = imeHeight   // real keyboard height only
            keyboardVisible = imeHeight > 0
            keyboardActive.value = imeHeight > 0
            if (!imeAnimating) { updateVideoOffset(); updateControlsOffset() }
            insets
        }
        // Follow the keyboard frame-by-frame as it slides, so the video pans with it
        // instead of jumping to the final position (native, no hand-rolled timing).
        ViewCompat.setWindowInsetsAnimationCallback(container,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_STOP) {
                override fun onPrepare(animation: WindowInsetsAnimationCompat) {
                    imeAnimating = true
                }
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    running: MutableList<WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    imeHeight = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
                    // NOTE: do NOT capture lastImeHeight here — mid-hide frames report
                    // tiny tail values (…1px→0) that would corrupt the panel height.
                    // The full settled height is captured in the apply listener instead.
                    updateVideoOffset(); updateControlsOffset()
                    return insets
                }
                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    imeAnimating = false
                    if (hidePanelAfterKeyboard) {
                        hidePanelAfterKeyboard = false
                        // Retire the pad now that the keyboard settled (or drop it if the
                        // keyboard never actually came up), so the state can't get stuck.
                        if (imeHeight > 0) dropPanelForKeyboard() else retirePanel()
                    } else { updateVideoOffset(); updateControlsOffset() }
                }
            })
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

    override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
        videoSurface = Surface(st)
        startStream()
    }

    private fun startStream() {
        val gen = ++streamGen
        videoRevealed = false   // a fresh stream (incl. rotation restart) re-reveals
        val dec = ScreenDecoder(
            surface = videoSurface ?: return,
            onVideoSize = { w, h ->
                runOnUiThread {
                    val changed = (w != videoW || h != videoH)
                    videoW = w; videoH = h
                    if (changed) applyAspect()
                    // Reveal from the centre ONCE per stream (onVideoSize may fire again
                    // on format changes — re-running the scale would flicker and fight a
                    // user zoom). The start delay lets the first frame land first.
                    if (!videoRevealed) {
                        videoRevealed = true
                        zoomScale = 0.92f; zoomPanX = 0f; zoomPanY = 0f; applyVideoTransform()
                        zoomReveal?.cancel()
                        zoomReveal = ValueAnimator.ofFloat(0.92f, 1f).apply {
                            startDelay = 90; duration = 320; interpolator = DecelerateInterpolator()
                            addUpdateListener { zoomScale = it.animatedValue as Float; applyVideoTransform() }
                            start()
                        }
                        fadeOverlay.animate().alpha(0f).setStartDelay(90).setDuration(280).start()
                    }
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

    /** Bottom space currently occupied by whichever panel is up (keyboard or trackpad).
     *  While a trackpad→keyboard swap is in flight we freeze it at the trackpad's
     *  reserved height so the video doesn't drift as the keyboard slides in — the
     *  final difference is settled once, smoothly, in [dropPanelForKeyboard]. */
    private fun bottomInset(): Int =
        if (hidePanelAfterKeyboard) panelReserved.toInt()
        else maxOf(imeHeight, panelReserved.toInt())

    /** The TextureView fills the container; the video is placed entirely via a
     *  [setTransform] matrix (letterbox + keyboard-fit + magnifier zoom), which
     *  transforms the texture on the GPU cleanly — no view-hierarchy scale ghosting. */
    private fun applyAspect() { updateVideoOffset() }

    /** Base letterbox height (px) of the video inside the full container. */
    private fun baseVideoHeight(): Float {
        val w = container.width; val h = container.height
        if (w <= 0 || h <= 0 || videoW <= 0 || videoH <= 0) return 0f
        val base = minOf(w.toFloat() / videoW, h.toFloat() / videoH)
        return videoH * base
    }

    /** Recompute the keyboard/trackpad fit, then re-apply the transform. */
    private fun updateVideoOffset() {
        val dispH = baseVideoHeight()
        if (dispH <= 0f) return
        val usableH = (container.height - bottomInset()).coerceAtLeast(1)
        fitScale = if (dispH > usableH) usableH / dispH else 1f   // shrink only if it wouldn't fit
        fitPanY = -bottomInset() / 2f                              // centre in the free area
        applyVideoTransform()
    }

    /** Vertical centre of the visible area — the screen ABOVE the keyboard/trackpad. */
    private fun usableCenterY() = (container.height - bottomInset()) / 2f

    /** Build and apply the video matrix: aspect letterbox · fit-to-usable · zoom · pan.
     *  The magnifier works entirely within the area above the panel, so zooming to a
     *  low point keeps it above the panel instead of hiding it underneath. */
    private fun applyVideoTransform() {
        val w = container.width; val h = container.height
        if (w <= 0 || h <= 0 || videoW <= 0 || videoH <= 0) return
        val base = minOf(w.toFloat() / videoW, h.toFloat() / videoH)
        val cx = w / 2f; val cyU = usableCenterY()
        val m = android.graphics.Matrix()
        m.setScale((videoW * base) / w, (videoH * base) / h, cx, h / 2f)  // aspect letterbox
        m.postScale(fitScale, fitScale, cx, h / 2f)            // shrink to fit above the panel
        m.postTranslate(0f, fitPanY)                           // slide it into the usable area
        m.postScale(zoomScale, zoomScale, cx, cyU)             // magnify about the usable centre
        m.postTranslate(zoomPanX, zoomPanY)                    // pan
        textureView.setTransform(m)
        textureView.invalidate()
    }

    /** Clamp the pan to the usable viewport (above the panel) — reach every edge, no further. */
    private fun clampZoomPan() {
        val w = container.width; val h = container.height
        if (w <= 0 || h <= 0 || videoW <= 0 || videoH <= 0) return
        val base = minOf(w.toFloat() / videoW, h.toFloat() / videoH)
        val usableH = (h - bottomInset()).coerceAtLeast(1)
        val dw = videoW * base * fitScale * zoomScale
        val dh = videoH * base * fitScale * zoomScale
        val maxX = ((dw - w) / 2f).coerceAtLeast(0f)
        val maxY = ((dh - usableH) / 2f).coerceAtLeast(0f)
        zoomPanX = zoomPanX.coerceIn(-maxX, maxX)
        zoomPanY = zoomPanY.coerceIn(-maxY, maxY)
    }

    /** Keep the toggle cluster just above whichever bottom panel is open. */
    private fun updateControlsOffset() {
        toggleRow?.translationY = -bottomInset().toFloat()
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

        // Control cluster (bottom-end): trackpad + keyboard toggles as native M3
        // Expressive icon buttons (Compose), lifted above whichever panel is open.
        val row = ComposeView(this).apply {
            setContent {
                AirbridgeTheme(themeMode = "dark") {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (trackpadActive.value) {
                            FilledIconButton(onClick = { setTrackpadMode(false) }) {
                                Icon(Icons.Filled.Mouse, contentDescription = "Gładzik")
                            }
                        } else {
                            FilledTonalIconButton(onClick = { setTrackpadMode(true) }) {
                                Icon(Icons.Filled.Mouse, contentDescription = "Gładzik")
                            }
                        }
                        if (keyboardActive.value) {
                            FilledIconButton(onClick = { toggleKeyboard() }) {
                                Icon(Icons.Filled.Keyboard, contentDescription = "Klawiatura")
                            }
                        } else {
                            FilledTonalIconButton(onClick = { toggleKeyboard() }) {
                                Icon(Icons.Filled.Keyboard, contentDescription = "Klawiatura")
                            }
                        }
                    }
                }
            }
        }
        toggleRow = row
        container.addView(row, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END
        ).apply { rightMargin = dp(16); bottomMargin = dp(16) })
        updateControlsOffset()
    }

    /** Trackpad panel height: match the keyboard exactly once we've seen it. */
    private fun panelHeight(): Int =
        if (lastImeHeight > 0) lastImeHeight
        else (container.height * trackpadPanelFraction).toInt().coerceAtLeast(dp(240))

    /** Animate the trackpad panel's reserved space + slide, panning the video with it. */
    private fun animatePanel(to: Float, onEnd: (() -> Unit)? = null) {
        panelAnimator?.cancel()
        panelAnimator = ValueAnimator.ofFloat(panelReserved, to).apply {
            duration = 260
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                panelReserved = it.animatedValue as Float
                trackpadPad.translationY = (panelTarget - panelReserved).coerceAtLeast(0f)
                updateVideoOffset(); updateControlsOffset()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: android.animation.Animator) { onEnd?.invoke() }
            })
            start()
        }
    }

    /** Slide the panel visually (translationY only) without touching reserved space. */
    private fun animatePanelSlide(toTransY: Float) {
        panelAnimator?.cancel()
        panelAnimator = ValueAnimator.ofFloat(trackpadPad.translationY, toTransY).apply {
            duration = 260
            interpolator = DecelerateInterpolator()
            addUpdateListener { trackpadPad.translationY = it.animatedValue as Float }
            start()
        }
    }

    /** Show/hide the bottom trackpad panel. Mutually exclusive with the keyboard.
     *  Idempotent and self-correcting — always drives the views to match `enabled`. */
    private fun setTrackpadMode(enabled: Boolean) {
        trackpadMode = enabled
        trackpadActive.value = enabled                   // drives the toggle's selected look
        hidePanelAfterKeyboard = false                   // an explicit toggle supersedes any pending swap
        if (enabled) {
            cursorX = 0.5f; cursorY = 0.5f
            panelTarget = panelHeight()
            (trackpadPad.layoutParams as FrameLayout.LayoutParams).height = panelTarget
            trackpadPad.visibility = View.VISIBLE
            trackpadPad.requestLayout()
            if (keyboardVisible) {
                // Swap keyboard → trackpad: hold the reserved space constant (the
                // keyboard already occupied it, so the video doesn't move), start the
                // pad off-screen and slide it up as the keyboard slides down.
                panelReserved = panelTarget.toFloat()
                trackpadPad.translationY = panelTarget.toFloat()
                animatePanelSlide(0f)
                hideKeyboard()
                updateVideoOffset(); updateControlsOffset()
            } else {
                animatePanel(panelTarget.toFloat())      // slide up, pan the video
            }
        } else {
            animatePanel(0f) { trackpadPad.visibility = View.GONE }
        }
    }

    /** Keyboard has fully risen during a trackpad → keyboard swap: retire the pad. */
    private fun dropPanelForKeyboard() {
        // The pad height and the actual keyboard height can differ — settle the
        // reserved space smoothly to the keyboard height instead of snapping.
        animatePanel(imeHeight.toFloat()) {
            panelReserved = 0f                 // the keyboard inset now holds the space
            trackpadPad.visibility = View.GONE
            updateVideoOffset(); updateControlsOffset()
        }
    }

    /** Hide the pad immediately (e.g. a pending swap where the keyboard never showed). */
    private fun retirePanel() {
        panelAnimator?.cancel()
        panelReserved = 0f
        trackpadPad.visibility = View.GONE
        updateVideoOffset(); updateControlsOffset()
    }

    /** Rounded, translucent-dark trackpad surface with a faint edge (Mac-trackpad look). */
    private fun trackpadPanelBackground(): android.graphics.drawable.GradientDrawable =
        android.graphics.drawable.GradientDrawable().apply {
            setColor(0xF21C1B1F.toInt())
            setStroke(dp(1), 0x33FFFFFF)   // faint edge so the pad reads as a distinct surface
            cornerRadii = floatArrayOf(dp(20).toFloat(), dp(20).toFloat(), dp(20).toFloat(), dp(20).toFloat(), 0f, 0f, 0f, 0f)
        }

    /** Faint markings inside the pad: a centre hairline hinting the click zones. */
    private fun addTrackpadMarkings(pad: FrameLayout) {
        val line = View(this).apply { setBackgroundColor(0x22FFFFFF) }
        pad.addView(line, FrameLayout.LayoutParams(dp(1), dp(72), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = dp(16)
        })
    }

    private fun toggleKeyboard() {
        if (keyboardVisible) hideKeyboard() else showKeyboard()
    }

    private fun showKeyboard() {
        // Swap trackpad → keyboard: keep the pad reserving its space until the
        // keyboard has fully risen (bottom inset stays constant, no jump), then
        // retire the pad in dropPanelForKeyboard() from the settled-inset callback.
        if (trackpadMode) {
            // Swap trackpad → keyboard: mark the trackpad off now (so its button
            // updates immediately), but keep the pad reserving its space until the
            // keyboard has fully risen, then retire it in onEnd — no video jump.
            trackpadMode = false
            trackpadActive.value = false
            hidePanelAfterKeyboard = true
        }
        keyboardInput.requestFocus()
        WindowInsetsControllerCompat(window, keyboardInput).show(WindowInsetsCompat.Type.ime())
        keyboardVisible = true
        keyboardActive.value = true
    }

    private fun hideKeyboard() {
        WindowInsetsControllerCompat(window, keyboardInput).hide(WindowInsetsCompat.Type.ime())
        keyboardVisible = false
        keyboardActive.value = false
    }

    /**
     * The screen layer is a passive magnifier — it does NOT control the Mac
     * (that is the trackpad's job). Pinch to zoom, drag (while zoomed) or two
     * fingers to pan, double-tap to toggle zoom. All transforms are local view
     * scale/translation; nothing is sent to the Mac.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun attachZoomControl(view: TextureView) {
        var prevFocusX = 0f; var prevFocusY = 0f
        scaleDetector = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                prevFocusX = d.focusX; prevFocusY = d.focusY; return true
            }
            override fun onScale(d: ScaleGestureDetector): Boolean {
                val s0 = zoomScale
                val s1 = (s0 * d.scaleFactor).coerceIn(1f, 4f)
                // Anchor the zoom to the pinch focus (scale pivot is the view centre,
                // so the pan must compensate) — otherwise the image lurches to an edge
                // and snaps back, leaving a ghost.
                val ax = d.focusX - textureView.width / 2f
                val ay = d.focusY - usableCenterY()
                zoomPanX = ax - (ax - zoomPanX) * (s1 / s0)
                zoomPanY = ay - (ay - zoomPanY) * (s1 / s0)
                // plus the focus's own movement, so two fingers also drag the image
                zoomPanX += d.focusX - prevFocusX
                zoomPanY += d.focusY - prevFocusY
                zoomScale = s1
                prevFocusX = d.focusX; prevFocusY = d.focusY
                clampZoomPan(); applyVideoTransform(); return true
            }
        })
        gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean { toggleZoom(e.x, e.y); return true }
            override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean {
                if (zoomScale > 1.01f && e2.pointerCount == 1) {   // one-finger pan only when zoomed
                    zoomPanX -= dx * zoomPanGain; zoomPanY -= dy * zoomPanGain
                    clampZoomPan(); applyVideoTransform(); return true
                }
                return false
            }
        })
        view.setOnTouchListener { _, e ->
            scaleDetector.onTouchEvent(e)
            gestureDetector.onTouchEvent(e)
            true
        }
    }

    /** Double-tap toggles between fit (1×) and 2.5×, zooming toward the tapped point. */
    private fun toggleZoom(tapX: Float, tapY: Float) {
        val target = if (zoomScale > 1.01f) 1f else 2.5f
        val fromScale = zoomScale
        val fromPanX = zoomPanX; val fromPanY = zoomPanY
        // Pan so the tapped point ends up centred in the usable area (above the panel).
        val cx = textureView.width / 2f; val cy = usableCenterY()
        val toPanX = if (target == 1f) 0f else -(tapX - cx) * target
        val toPanY = if (target == 1f) 0f else -(tapY - cy) * target
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 240; interpolator = DecelerateInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                zoomScale = fromScale + (target - fromScale) * t
                zoomPanX = fromPanX + (toPanX - fromPanX) * t
                zoomPanY = fromPanY + (toPanY - fromPanY) * t
                clampZoomPan(); applyVideoTransform()
            }
            start()
        }
    }

    /**
     * Relative trackpad control. One finger moves a virtual cursor by finger
     * deltas (with acceleration) via `move` — never drags. A one-finger tap
     * left-clicks; a two-finger tap right-clicks; a two-finger move scrolls.
     * Absolute finger position is irrelevant — only motion matters.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun attachTrackpadControl(view: View) {
        var lastX = 0f; var lastY = 0f      // last position of the tracked finger
        var downX = 0f; var downY = 0f      // press point (tap vs move discrimination)
        var downTime = 0L
        var moved = false                   // finger travelled beyond tap slop
        var scrolling = false               // two-finger scroll in progress
        var twoFinger = false               // a second finger touched during this gesture
        var didScroll = false               // two-finger midpoint actually moved
        var consumed = false                // a click already fired; suppress the tap on UP
        var anchorX = 0f; var anchorY = 0f  // two-finger scroll anchor
        val tapSlop = 24f
        val tapTimeoutMs = 250L

        view.setOnTouchListener { v, e ->
            val c = client ?: return@setOnTouchListener true
            val w = v.width.toFloat(); val h = v.height.toFloat()
            if (w <= 0f || h <= 0f) return@setOnTouchListener true
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = e.x; lastY = e.y; downX = e.x; downY = e.y
                    downTime = e.eventTime
                    moved = false; scrolling = false; twoFinger = false
                    didScroll = false; consumed = false
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    if (e.pointerCount >= 2) {
                        twoFinger = true
                        scrolling = true; didScroll = false
                        anchorX = (e.getX(0) + e.getX(1)) / 2
                        anchorY = (e.getY(0) + e.getY(1)) / 2
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    if (scrolling && e.pointerCount >= 2) {
                        val cx = (e.getX(0) + e.getX(1)) / 2
                        val cy = (e.getY(0) + e.getY(1)) / 2
                        val dsx = cx - anchorX; val dsy = cy - anchorY
                        if (kotlin.math.hypot(dsx, dsy) > tapSlop) didScroll = true
                        c.sendScroll(dsx * trackpadScrollGain, dsy * trackpadScrollGain)
                        anchorX = cx; anchorY = cy
                    } else if (!twoFinger && !consumed) {
                        val dx = e.x - lastX; val dy = e.y - lastY
                        lastX = e.x; lastY = e.y
                        if (kotlin.math.hypot(e.x - downX, e.y - downY) > tapSlop) moved = true
                        val speed = kotlin.math.hypot(dx, dy)
                        val accel = (1f + speed * trackpadAccelK).coerceAtMost(trackpadAccelMax)
                        cursorX = (cursorX + (dx / w) * trackpadGain * accel).coerceIn(0f, 1f)
                        cursorY = (cursorY + (dy / h) * trackpadGain * accel).coerceIn(0f, 1f)
                        c.sendInput(0u, cursorX, cursorY)   // bare move — never a drag
                    }
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    // Dropping from two fingers to one: a quick, still two-finger
                    // touch is a right-click. Suppress the trailing single-finger tap.
                    if (twoFinger && e.pointerCount == 2 && !didScroll &&
                        (e.eventTime - downTime) < tapTimeoutMs) {
                        c.sendInput(4u, cursorX, cursorY)   // right click
                        consumed = true
                    }
                    scrolling = false
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (!twoFinger && !consumed &&
                        !moved && (e.eventTime - downTime) < tapTimeoutMs) {
                        c.sendInput(1u, cursorX, cursorY); c.sendInput(2u, cursorX, cursorY)  // tap = left click
                    }
                    scrolling = false; twoFinger = false; consumed = false
                }
            }
            true
        }
    }

    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) { updateVideoOffset() }
    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
        teardown()
        return true
    }

    override fun onDestroy() { teardown(); super.onDestroy() }

    private fun teardown() {
        client?.close(); client = null
        decoder?.stop(); decoder = null
        videoSurface?.release(); videoSurface = null
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_MODE = "mode"
        const val EXTRA_CERT_FINGERPRINT = "certFingerprint"
    }
}
