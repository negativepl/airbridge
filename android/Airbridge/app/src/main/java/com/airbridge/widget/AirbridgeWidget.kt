package com.airbridge.widget

import android.content.Context
import android.os.Build
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.size
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.unit.ColorProvider
import com.airbridge.R

/**
 * Home screen widget: AirBridge's five quick actions in Android's canonical
 * Material 3 Expressive "Expressive Toolbar" layout, a four-sided cookie with
 * the clipboard in the middle and file, photo, scan and the Mac screen in the
 * corners. Each button runs in [WidgetActionActivity], without opening the app.
 *
 * The layout follows Google's reference implementation (android/platform-samples,
 * appwidgets ExpressiveToolbarLayout, Apache License 2.0, Copyright 2025 The
 * Android Open Source Project): the same breakpoints, scaling and colours.
 */
class AirbridgeWidget : GlanceAppWidget() {
    // Exact: one layout for the size on screen, and no per-size copies held by
    // the launcher (as Responsive would).
    override val sizeMode: SizeMode = SizeMode.Exact

    // The widget picker shows the full layout (all five buttons), not the
    // drop size, at which only the centre button would fit.
    override val previewSizeMode = SizeMode.Responsive(setOf(DpSize(182.dp, 182.dp)))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                WidgetContent(context)
            }
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent {
            GlanceTheme {
                WidgetContent(context)
            }
        }
    }

    @Composable
    private fun WidgetContent(context: Context) {
        fun button(@DrawableRes icon: Int, label: Int, action: String) = ToolbarButton(
            iconRes = icon,
            contentDescription = context.getString(label),
            onClick = actionStartActivity(WidgetActionActivity.intent(context, action)),
        )
        ExpressiveToolbar(
            centerButton = button(R.drawable.ic_widget_clipboard, R.string.action_send_clipboard, WidgetActionActivity.ACTION_CLIPBOARD),
            cornerButtons = listOf(
                button(R.drawable.ic_widget_file, R.string.action_send_file, WidgetActionActivity.ACTION_FILE),
                button(R.drawable.ic_widget_photo, R.string.action_send_photo, WidgetActionActivity.ACTION_PHOTO),
                button(R.drawable.ic_widget_scan, R.string.quick_scan, WidgetActionActivity.ACTION_SCAN),
                button(R.drawable.ic_widget_mac_screen, R.string.quick_mac_screen, WidgetActionActivity.ACTION_MAC_SCREEN),
            ),
        )
    }
}

class AirbridgeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AirbridgeWidget()
}

private data class ToolbarButton(
    @DrawableRes val iconRes: Int,
    val contentDescription: String,
    val onClick: Action,
)

/**
 * The cookie fills the shorter side of the widget. Below a 2x2 cell (about
 * 140 dp) only the centre button fits with accessible tap targets; from there
 * up the four corner buttons join it and the centre one gets its filled
 * container.
 */
@Composable
private fun ExpressiveToolbar(centerButton: ToolbarButton, cornerButtons: List<ToolbarButton>) {
    val size = LocalSize.current
    val cookieSize = size.width.coerceAtMost(size.height)
    val modifier = GlanceModifier
        .size(cookieSize)
        .appWidgetBackground()
        .background(
            imageProvider = ImageProvider(R.drawable.widget_cookie_background),
            colorFilter = ColorFilter.tint(GlanceTheme.colors.widgetBackground),
        )

    Box(contentAlignment = Alignment.Center, modifier = GlanceModifier.fillMaxSize()) {
        if (cookieSize < AllButtonsMinSize) {
            Box(contentAlignment = Alignment.Center, modifier = modifier) {
                ShapedButton(
                    button = centerButton,
                    clickableSize = 48.dp,
                    containerSize = 48.dp,
                    iconSize = 24.dp,
                    containerColor = Transparent,
                    contentColor = GlanceTheme.colors.primary,
                    cornerRadius = CornerMedium,
                )
            }
        } else {
            // Reference design: a 48 dp container and a 24 dp icon at 182 dp.
            val containerSize = Dp(cookieSize.value * 26 / 100)
            val iconSize = Dp(cookieSize.value * 13 / 100)
            // Rounded corners need Android 12+; older releases keep the plain icon.
            val filled = Build.VERSION.SDK_INT > Build.VERSION_CODES.S
            Box(contentAlignment = Alignment.Center, modifier = modifier) {
                // Centre button under the corner grid, with the larger tap target.
                ShapedButton(
                    button = centerButton,
                    clickableSize = CenterTapTarget,
                    containerSize = containerSize,
                    iconSize = iconSize,
                    containerColor = if (filled) GlanceTheme.colors.tertiary else Transparent,
                    contentColor = if (filled) GlanceTheme.colors.onTertiary else GlanceTheme.colors.primary,
                    cornerRadius = CornerMedium,
                )
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    cornerButtons.chunked(2).forEach { row ->
                        Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                            row.forEach { button ->
                                Box(
                                    contentAlignment = Alignment.Center,
                                    modifier = GlanceModifier.fillMaxHeight().defaultWeight(),
                                ) {
                                    ShapedButton(
                                        button = button,
                                        clickableSize = containerSize.coerceAtLeast(CornerTapTarget),
                                        containerSize = containerSize,
                                        iconSize = iconSize,
                                        containerColor = Transparent,
                                        contentColor = GlanceTheme.colors.primary,
                                        cornerRadius = CornerFull,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** A tap target with its own (smaller or equal) coloured container and a tinted icon. */
@Composable
private fun ShapedButton(
    button: ToolbarButton,
    clickableSize: Dp,
    containerSize: Dp,
    iconSize: Dp,
    containerColor: ColorProvider,
    contentColor: ColorProvider,
    cornerRadius: Dp,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = GlanceModifier
            .size(clickableSize)
            .cornerRadius(cornerRadius)
            .semantics { contentDescription = button.contentDescription }
            .clickable(button.onClick),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = GlanceModifier
                .size(containerSize)
                .background(containerColor)
                .cornerRadius(cornerRadius),
        ) {
            Image(
                provider = ImageProvider(button.iconRes),
                contentDescription = null,
                colorFilter = ColorFilter.tint(contentColor),
                modifier = GlanceModifier.size(iconSize),
            )
        }
    }
}

private val AllButtonsMinSize = 140.dp
private val CenterTapTarget = 60.dp
private val CornerTapTarget = 48.dp
/** M3 shape tokens: medium (16 dp) for the centre button, full for the corners. */
private val CornerMedium = 16.dp
private val CornerFull = 100.dp
private val Transparent = androidx.glance.color.ColorProvider(Color.Transparent, Color.Transparent)
