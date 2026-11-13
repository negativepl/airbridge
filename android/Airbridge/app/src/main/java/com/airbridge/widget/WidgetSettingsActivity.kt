package com.airbridge.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.MotionEvent
import android.widget.FrameLayout
import android.widget.RemoteViews
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderState
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.rememberSliderState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.glance.GlanceId
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.compose
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.lifecycleScope
import com.airbridge.R
import com.airbridge.ui.AirbridgeTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The launcher's "Widget settings" for one placed widget (long press, pencil):
 * colours, theme and background transparency. The window shows the real
 * wallpaper (Theme.Airbridge.WidgetSettings), with a live preview of the
 * widget on it above the settings, so transparency is judged where it lands.
 * Changes apply to the widget as they are made.
 */
class WidgetSettingsActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val widget = widgetFor(appWidgetId)
        if (widget == null) {
            finish()
            return
        }
        // Settings are optional and saved as they change: leaving keeps the widget.
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))

        val themeMode = getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE).getString("theme_mode", "system") ?: "system"
        lifecycleScope.launch {
            val glanceId = GlanceAppWidgetManager(this@WidgetSettingsActivity).getGlanceIdBy(appWidgetId)
            val initial = WidgetSettings.from(
                getAppWidgetState(this@WidgetSettingsActivity, PreferencesGlanceStateDefinition, glanceId)
            )
            setContent {
                AirbridgeTheme(themeMode = themeMode) {
                    SettingsScreen(
                        widget = widget,
                        glanceId = glanceId,
                        previewSize = previewSize(appWidgetId, widget),
                        initial = initial,
                        onDone = { finish() },
                    )
                }
            }
        }
    }

    @Composable
    private fun SettingsScreen(
        widget: GlanceAppWidget,
        glanceId: GlanceId,
        previewSize: DpSize,
        initial: WidgetSettings,
        onDone: () -> Unit,
    ) {
        var settings by remember { mutableStateOf(initial) }
        var preview by remember { mutableStateOf<RemoteViews?>(null) }
        val context = this

        LaunchedEffect(settings) {
            val state = mutablePreferencesOf().also { settings.writeTo(it) }
            preview = widget.compose(context, glanceId, size = previewSize, state = state)
            // Let a slider drag settle before writing the widget itself.
            delay(SAVE_DELAY_MS)
            updateAppWidgetState(context, glanceId) { settings.writeTo(it) }
            widget.update(context, glanceId)
        }

        Column(modifier = Modifier.fillMaxSize()) {
            // The wallpaper shows through here, with the widget on it.
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxWidth().weight(1f).statusBarsPadding(),
            ) {
                preview?.let { views ->
                    AndroidView(
                        modifier = Modifier.size(previewSize.width, previewSize.height),
                        factory = { TouchlessFrame(it) },
                        update = { frame ->
                            frame.removeAllViews()
                            frame.addView(views.apply(frame.context, frame))
                        },
                    )
                }
            }
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainer,
                // A sheet over the wallpaper: rounded on top only.
                shape = MaterialTheme.shapes.extraLarge.copy(bottomStart = CornerSize(0.dp), bottomEnd = CornerSize(0.dp)),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    modifier = Modifier.navigationBarsPadding().padding(horizontal = 24.dp, vertical = 24.dp),
                ) {
                    Text(
                        stringResource(R.string.widget_settings_title),
                        style = MaterialTheme.typography.titleLargeEmphasized,
                    )
                    Section(stringResource(R.string.widget_settings_colors)) {
                        Choice(
                            options = listOf(
                                WidgetColors.WALLPAPER to R.string.widget_colors_wallpaper,
                                WidgetColors.MONOCHROME to R.string.widget_colors_monochrome,
                            ),
                            selected = settings.colors,
                            onSelect = { settings = settings.copy(colors = it) },
                        )
                    }
                    Section(stringResource(R.string.widget_settings_theme)) {
                        Choice(
                            options = listOf(
                                WidgetThemeMode.SYSTEM to R.string.settings_theme_system,
                                WidgetThemeMode.LIGHT to R.string.settings_theme_light,
                                WidgetThemeMode.DARK to R.string.settings_theme_dark,
                            ),
                            selected = settings.theme,
                            onSelect = { settings = settings.copy(theme = it) },
                        )
                    }
                    val transparency = rememberSliderState(value = 1f - initial.backgroundOpacity)
                    val haptics = LocalHapticFeedback.current
                    // Sets the transparency, ticking when it lands on a suggested value.
                    fun setTransparency(value: Float) {
                        if (value != transparency.value && value in TransparencyStops) {
                            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                        }
                        transparency.value = value
                        settings = settings.copy(backgroundOpacity = 1f - value)
                    }
                    Section(stringResource(R.string.widget_settings_transparency, (transparency.value * 100).roundToInt())) {
                        Slider(
                            state = transparency,
                            // Continuous, but the suggested values pull the thumb in
                            // while dragging nearby...
                            onValueChange = { setTransparency(snapToStop(it, StopPull)) },
                            // ...and a quick drag released close to one lands on it.
                            onValueChangeFinished = { setTransparency(snapToStop(transparency.value, StopLanding)) },
                            track = { state -> TransparencyTrack(state) },
                        )
                    }
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Button(onClick = onDone) { Text(stringResource(R.string.widget_settings_done)) }
                    }
                }
            }
        }
    }

    /**
     * The standard slider track with the suggested values marked on it, the
     * way a stepped slider marks its steps: same dot, same colours, placed with
     * the track's own geometry, and left out next to the thumb. The end of the
     * track already has its stop indicator.
     */
    @Composable
    private fun TransparencyTrack(state: SliderState) {
        val colors = SliderDefaults.colors()
        SliderDefaults.Track(
            sliderState = state,
            trackCornerSize = TrackCornerSize,
            colors = colors,
            modifier = Modifier.drawWithContent {
                drawContent()
                val corner = TrackCornerSize.toPx()
                val thumb = size.width * state.coercedFraction()
                val clearance = ThumbClearance.toPx()
                TransparencyStops.dropLast(1).forEach { stop ->
                    val x = corner + (size.width - 2 * corner) * stop
                    if (abs(x - thumb) < clearance) return@forEach
                    val color = if (x < thumb) colors.activeTickColor else colors.inactiveTickColor
                    val drawnX = if (layoutDirection == LayoutDirection.Rtl) size.width - x else x
                    with(SliderDefaults) { drawStopIndicator(Offset(drawnX, center.y), SliderDefaults.TickSize, color) }
                }
            },
        )
    }

    @Composable
    private fun Section(title: String, content: @Composable () -> Unit) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            content()
        }
    }

    @Composable
    private fun <T> Choice(options: List<Pair<T, Int>>, selected: T, onSelect: (T) -> Unit) {
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, (value, label) ->
                SegmentedButton(
                    selected = value == selected,
                    onClick = { onSelect(value) },
                    shape = SegmentedButtonDefaults.itemShape(index, options.size),
                    label = { Text(stringResource(label), maxLines = 1) },
                )
            }
        }
    }

    /** The widget class behind [appWidgetId], from the provider the launcher placed. */
    private fun widgetFor(appWidgetId: Int): GlanceAppWidget? {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return null
        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(appWidgetId)?.provider?.className
        return when (provider) {
            ClipboardWidgetReceiver::class.java.name -> ClipboardWidget()
            AirbridgeWidgetReceiver::class.java.name -> AirbridgeWidget()
            ToolbarWidgetReceiver::class.java.name -> ToolbarWidget()
            else -> null
        }
    }

    /** The widget's size on the home screen (portrait), or its default size before it has one. */
    private fun previewSize(appWidgetId: Int, widget: GlanceAppWidget): DpSize {
        val options = AppWidgetManager.getInstance(this).getAppWidgetOptions(appWidgetId)
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        if (width > 0 && height > 0) return DpSize(width.dp, height.dp)
        return when (widget) {
            is ClipboardWidget -> DpSize(64.dp, 64.dp)
            is ToolbarWidget -> DpSize(300.dp, 72.dp)
            else -> DpSize(190.dp, 190.dp)
        }
    }

    /** Hosts the preview without letting taps reach its buttons. */
    private class TouchlessFrame(context: Context) : FrameLayout(context) {
        override fun onInterceptTouchEvent(ev: MotionEvent?) = true
    }

    private companion object {
        const val SAVE_DELAY_MS = 250L

        /** Suggested transparencies: 0, 25, 50, 75 and 100 %. */
        val TransparencyStops = listOf(0f, 0.25f, 0.5f, 0.75f, 1f)

        /** How close (of the full range) a stop pulls the thumb while dragging. */
        const val StopPull = 0.03f

        /** How close a release must be for the thumb to settle on a stop. */
        const val StopLanding = 0.07f

        /** Half the standard 16 dp track: its rounded ends. */
        val TrackCornerSize = 8.dp

        /** Room the thumb keeps clear around itself: its gap to the track plus half its width. */
        val ThumbClearance = 8.dp

        fun SliderState.coercedFraction() = value.coerceIn(0f, 1f)

        fun snapToStop(value: Float, within: Float): Float =
            TransparencyStops.firstOrNull { abs(it - value) <= within } ?: value
    }
}

