package com.airbridge.mirror

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
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
import androidx.window.layout.WindowMetricsCalculator
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.airbridge.ui.AirbridgeTheme

/**
 * Reverse mirror viewer: shows the Mac's screen on the phone. Display-only for
 * now — connects to the Mac mirror server, sends ReverseHello, decodes the
 * incoming stream onto a [SurfaceView] that is sized and placed (letterboxed to
 * the Mac's aspect ratio, fitted above the keyboard/trackpad panel) by layout.
 * The video view is display-only: there is no magnifier, and the trackpad panel
 * carries the input.
 */
class ReverseMirrorActivity : ComponentActivity(), SurfaceHolder.Callback {

    private var client: ReverseMirrorClient? = null
    private var decoder: ScreenDecoder? = null

    private lateinit var container: FrameLayout
    // SurfaceView: SurfaceFlinger composes it directly (no app-side redraw), so each
    // decoded frame is presented on the vsync its presentation timestamp asks for.
    // No magnifier — the video is only letterboxed and fitted above the panel.
    private lateinit var surfaceView: SurfaceView
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

    // MARK: - Video placement
    private var fitScale = 1f           // extra downscale so the video fits above a panel
    private var videoReveal: ValueAnimator? = null
    private var videoRevealed = false   // reveal animation runs once per stream, not per frame
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

        // The container is black (letterbox bars); the SurfaceView renders the video.
        container = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        surfaceView = SurfaceView(this).apply {
            holder.addCallback(this@ReverseMirrorActivity)
        }
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

    override fun surfaceCreated(holder: SurfaceHolder) {
        videoSurface = holder.surface.also { surface ->
            // The Mac sends 60 fps; let the panel settle on a matching refresh
            // rate so each frame lands on a whole number of vsyncs.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                surface.setFrameRate(60f, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
            }
        }
        startStream()
    }

    private fun startStream() {
        val gen = ++streamGen
        videoRevealed = false   // a fresh stream (incl. rotation restart) re-reveals
        videoReveal?.cancel()
        surfaceView.scaleX = 1f; surfaceView.scaleY = 1f
        val dec = ScreenDecoder(
            surface = videoSurface ?: return,
            onVideoSize = { w, h ->
                runOnUiThread {
                    val changed = (w != videoW || h != videoH)
                    videoW = w; videoH = h
                    if (changed) applyAspect()
                    // Reveal from the centre ONCE per stream (onVideoSize may fire again
                    // on format changes — re-running the scale would flicker). The start
                    // delay lets the first frame land first. View scale pivots on the
                    // view's centre, i.e. the centre of the placed video.
                    if (!videoRevealed) {
                        videoRevealed = true
                        videoReveal?.cancel()
                        surfaceView.scaleX = 0.92f; surfaceView.scaleY = 0.92f
                        videoReveal = ValueAnimator.ofFloat(0.92f, 1f).apply {
                            startDelay = 90; duration = 320; interpolator = DecelerateInterpolator()
                            addUpdateListener {
                                val s = it.animatedValue as Float
                                surfaceView.scaleX = s; surfaceView.scaleY = s
                            }
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

    /** Full physical size of the current screen, in pixels (the Fold reports the open panel once unfolded). */
    private fun realDisplaySize(): Pair<Int, Int> {
        val bounds = WindowMetricsCalculator.getOrCreate().computeMaximumWindowMetrics(this).bounds
        return bounds.width() to bounds.height()
    }

    /** Bottom space currently occupied by whichever panel is up (keyboard or trackpad).
     *  While a trackpad→keyboard swap is in flight we freeze it at the trackpad's
     *  reserved height so the video doesn't drift as the keyboard slides in — the
     *  final difference is settled once, smoothly, in [dropPanelForKeyboard]. */
    private fun bottomInset(): Int =
        if (hidePanelAfterKeyboard) panelReserved.toInt()
        else maxOf(imeHeight, panelReserved.toInt())

    /** The video is placed by layout: [updateVideoOffset] sizes and positions the
     *  SurfaceView to the letterboxed, keyboard-fitted video rect. */
    private fun applyAspect() { updateVideoOffset() }

    /** Base letterbox height (px) of the video inside the full container. */
    private fun baseVideoHeight(): Float {
        val w = container.width; val h = container.height
        if (w <= 0 || h <= 0 || videoW <= 0 || videoH <= 0) return 0f
        val base = minOf(w.toFloat() / videoW, h.toFloat() / videoH)
        return videoH * base
    }

    /** Recompute the keyboard/trackpad fit, then size and place the video view:
     *  aspect letterbox, shrunk only if it would not fit above the panel, centred
     *  horizontally and on the free area's vertical centre. No-op until both the
     *  container and the video size are known. */
    private fun updateVideoOffset() {
        val dispH = baseVideoHeight()
        if (dispH <= 0f) return
        val w = container.width; val h = container.height
        val usableH = (h - bottomInset()).coerceAtLeast(1)
        fitScale = if (dispH > usableH) usableH / dispH else 1f   // shrink only if it wouldn't fit
        val base = minOf(w.toFloat() / videoW, h.toFloat() / videoH)
        val vw = Math.round(videoW * base * fitScale)
        val vh = Math.round(videoH * base * fitScale)
        val left = Math.round((w - vw) / 2f)
        val top = Math.round(usableCenterY() - vh / 2f)
        val lp = surfaceView.layoutParams as FrameLayout.LayoutParams
        if (lp.width == vw && lp.height == vh && lp.leftMargin == left && lp.topMargin == top &&
            lp.gravity == (Gravity.TOP or Gravity.START)) return
        lp.width = vw; lp.height = vh
        lp.leftMargin = left; lp.topMargin = top
        lp.gravity = Gravity.TOP or Gravity.START
        surfaceView.layoutParams = lp
    }

    /** Vertical centre of the visible area — the screen ABOVE the keyboard/trackpad. */
    private fun usableCenterY() = (container.height - bottomInset()) / 2f

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

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { updateVideoOffset() }
    override fun surfaceDestroyed(holder: SurfaceHolder) { teardown() }

    override fun onDestroy() { teardown(); super.onDestroy() }

    private fun teardown() {
        client?.close(); client = null
        decoder?.stop(); decoder = null
        videoSurface = null   // the holder's surface is owned by the SurfaceView; never release it here
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_MODE = "mode"
        const val EXTRA_CERT_FINGERPRINT = "certFingerprint"
    }
}
