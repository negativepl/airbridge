package com.airbridge.widget

import android.content.Context
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.currentState
import androidx.datastore.preferences.core.Preferences
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.components.Scaffold
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.size
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import com.airbridge.R
import com.airbridge.service.AirbridgeService

private val Transparent = androidx.glance.color.ColorProvider(androidx.compose.ui.graphics.Color.Transparent, androidx.compose.ui.graphics.Color.Transparent)

/*
 * AirBridge's home screen widgets. All three run their buttons in
 * WidgetActionActivity (no app opens) and sit in Glance's Scaffold, the
 * launcher's own rounded rectangle, so opening and closing from a widget
 * animates cleanly to its edge.
 */

/**
 * Base for the widgets: one layout for the exact size on screen, in the
 * colours, theme and background opacity set for that widget (WidgetSettings).
 */
abstract class AirbridgeGlanceWidget(previewSize: DpSize) : GlanceAppWidget() {
    // Exact: one layout for the size on screen, and no per-size copies held by
    // the launcher (as Responsive would).
    override val sizeMode: SizeMode = SizeMode.Exact

    // The widget picker shows the widget at its intended size.
    override val previewSizeMode = SizeMode.Responsive(setOf(previewSize))

    @Composable
    protected abstract fun Content(context: Context, settings: WidgetSettings)

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val settings = WidgetSettings.from(currentState<Preferences>())
            val connected by AirbridgeService.isConnected.collectAsState()
            CompositionLocalProvider(LocalMacConnected provides connected) {
                WidgetTheme(context, settings) { Content(context, settings) }
            }
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val settings = WidgetSettings()
        provideContent { WidgetTheme(context, settings) { Content(context, settings) } }
    }
}

/** 1x1: the clipboard alone, the whole widget one filled tertiary button. */
class ClipboardWidget : AirbridgeGlanceWidget(DpSize(64.dp, 64.dp)) {
    @Composable
    override fun Content(context: Context, settings: WidgetSettings) {
        val button = clipboardButton(context)
        val alpha = if (LocalMacConnected.current) 1f else DisabledAlpha
        WidgetBackground(GlanceTheme.colors.tertiary, settings.backgroundOpacity * alpha) {
            Scaffold(backgroundColor = Transparent, horizontalPadding = 0.dp) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = GlanceModifier
                        .fillMaxSize()
                        .semantics { contentDescription = button.contentDescription }
                        .clickable(button.onClick),
                ) {
                    Image(
                        provider = ImageProvider(button.iconRes),
                        contentDescription = null,
                        alpha = alpha,
                        colorFilter = ColorFilter.tint(GlanceTheme.colors.onTertiary),
                        modifier = GlanceModifier.size(28.dp),
                    )
                }
            }
        }
    }
}

/**
 * 2x2: the quick actions. Header with the clipboard as the featured pill, the
 * other four in a grid below. The class keeps its original name so widgets
 * already on a home screen stay in place.
 */
class AirbridgeWidget : AirbridgeGlanceWidget(DpSize(190.dp, 190.dp)) {
    @Composable
    override fun Content(context: Context, settings: WidgetSettings) = QuickActionsToolbar(context, settings)
}

/** 4x1: the same toolbar as one row. */
class ToolbarWidget : AirbridgeGlanceWidget(DpSize(300.dp, 72.dp)) {
    @Composable
    override fun Content(context: Context, settings: WidgetSettings) = QuickActionsToolbar(context, settings)
}

/** Redraws every placed AirBridge widget (connection changes, wallpaper colours held for a fixed theme). */
suspend fun refreshAllWidgets(context: Context) {
    for (widget in listOf(ClipboardWidget(), AirbridgeWidget(), ToolbarWidget())) {
        runCatching { widget.updateAll(context) }
            .onFailure { android.util.Log.w("AirbridgeWidget", "Widgets not refreshed", it) }
    }
}

class ClipboardWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ClipboardWidget()
}

class AirbridgeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AirbridgeWidget()
}

class ToolbarWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ToolbarWidget()
}

@Composable
private fun QuickActionsToolbar(context: Context, settings: WidgetSettings) {
    ToolbarLayout(
        appName = context.getString(R.string.app_name),
        appIconRes = R.drawable.ic_notification,
        featured = clipboardButton(context),
        buttons = listOf(
            widgetButton(context, R.drawable.ic_widget_file, R.string.action_send_file, WidgetActionActivity.ACTION_FILE),
            widgetButton(context, R.drawable.ic_widget_photo, R.string.action_send_photo, WidgetActionActivity.ACTION_PHOTO),
            widgetButton(context, R.drawable.ic_widget_scan, R.string.quick_scan, WidgetActionActivity.ACTION_SCAN),
            widgetButton(context, R.drawable.ic_widget_mac_screen, R.string.quick_mac_screen, WidgetActionActivity.ACTION_MAC_SCREEN),
        ),
        backgroundOpacity = settings.backgroundOpacity,
    )
}

private fun clipboardButton(context: Context) =
    widgetButton(context, R.drawable.ic_widget_clipboard, R.string.action_send_clipboard, WidgetActionActivity.ACTION_CLIPBOARD)

private fun widgetButton(context: Context, @DrawableRes icon: Int, @StringRes label: Int, action: String) =
    WidgetButton(
        iconRes = icon,
        contentDescription = context.getString(label),
        onClick = actionStartActivity(WidgetActionActivity.intent(context, action)),
    )
