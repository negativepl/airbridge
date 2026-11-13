package com.airbridge.widget

import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.components.Scaffold
import androidx.glance.appwidget.components.TitleBar
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.unit.ColorProvider

/*
 * Android's canonical "Toolbar" widget layout (Material 3), adapted from
 * Google's reference implementation: android/platform-samples, appwidgets
 * ToolBarLayout, Buttons and LayoutComponents (Apache License 2.0, Copyright
 * 2025 The Android Open Source Project). The widget sits in Glance's Scaffold,
 * whose background is the launcher's own rounded rectangle, so the launcher's
 * open and close animations land exactly on the widget's edge.
 */

/** One widget button: an icon, its spoken label and what a tap does. */
data class WidgetButton(
    @DrawableRes val iconRes: Int,
    val contentDescription: String,
    val onClick: Action,
)

/**
 * The brand icon, the featured action (filled, tertiary) and the regular
 * actions (tonal), laid out for the size on screen:
 * - one row (height below 128 dp), or one column (width below 128 dp), of as
 *   many items as fit with 48 dp tap targets;
 * - a header (icon, title when it fits, featured action as a pill) above a
 *   2x2 grid of the regular actions, once that fits;
 * - otherwise a two-row grid starting with the icon and the featured action.
 */
@Composable
fun ToolbarLayout(
    appName: String,
    @DrawableRes appIconRes: Int,
    featured: WidgetButton,
    buttons: List<WidgetButton>,
    backgroundOpacity: Float,
) {
    val size = LocalSize.current
    if (size.height < 128.dp && size.height > CompactBarHeight) {
        // One row: the launcher sizes widgets in whole cells, so the bar keeps
        // the M3 toolbar height and sits centred in its cell, as the search
        // bar does, instead of filling the whole row.
        Box(modifier = GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Box(modifier = GlanceModifier.fillMaxWidth().height(CompactBarHeight)) {
                WidgetBackground(GlanceTheme.colors.widgetBackground, backgroundOpacity) {
                    CompactBar(appIconRes, featured, buttons, size.width)
                }
            }
        }
        return
    }
    WidgetBackground(GlanceTheme.colors.widgetBackground, backgroundOpacity) {
        ToolbarContent(appName, appIconRes, featured, buttons)
    }
}

/** The one-row bar: icon, featured action and as many actions as fit, each a 48 dp target. */
@Composable
private fun CompactBar(
    @DrawableRes appIconRes: Int,
    featured: WidgetButton,
    buttons: List<WidgetButton>,
    width: Dp,
) {
    Scaffold(
        modifier = GlanceModifier.padding(vertical = CompactBarPadding),
        backgroundColor = Transparent,
        horizontalPadding = CompactBarPadding,
    ) {
        val items: List<@Composable () -> Unit> =
            listOf<@Composable () -> Unit>({ FluidAppIcon(appIconRes) }, { FluidFeaturedButton(featured, filled = true) }) +
                buttons.map { button -> { FluidButton(button, filled = true) } }
        // n items have n - 1 gaps: add one gap to the length to divide evenly.
        val fit = ((width - CompactBarPadding * 2 + ItemSpacing) / (MinButtonSize + ItemSpacing)).toInt()
        SpacedRow(items.take(fit), GlanceModifier.fillMaxSize())
    }
}

@Composable
private fun ToolbarContent(
    appName: String,
    @DrawableRes appIconRes: Int,
    featured: WidgetButton,
    buttons: List<WidgetButton>,
) {
    val size = LocalSize.current
    val filled = size.height >= 72.dp && size.width >= 72.dp
    val appIcon: @Composable () -> Unit = { FluidAppIcon(appIconRes) }
    val featuredItem: @Composable () -> Unit = { FluidFeaturedButton(featured, filled) }
    val buttonItems: List<@Composable () -> Unit> = buttons.map { { FluidButton(it, filled) } }

    when {
        size.height < 128.dp || size.width < 128.dp -> {
            val horizontal = size.height < 128.dp
            Scaffold(modifier = GlanceModifier.padding(vertical = WidgetPadding), backgroundColor = Transparent, horizontalPadding = WidgetPadding) {
                val length = if (horizontal) size.width else size.height
                // n items have n - 1 gaps: add one gap to the length to divide evenly.
                val fit = ((length + ItemSpacing) / (MinButtonSize + ItemSpacing)).toInt()
                val items = (listOf(appIcon, featuredItem) + buttonItems).take(fit)
                if (horizontal) SpacedRow(items, GlanceModifier.fillMaxSize())
                else SpacedColumn(items, GlanceModifier.fillMaxSize())
            }
        }
        size.height >= HeaderGridMinHeight -> {
            Scaffold(
                modifier = GlanceModifier.padding(bottom = WidgetPadding),
                backgroundColor = Transparent,
                horizontalPadding = WidgetPadding,
                titleBar = {
                    TitleBar(
                        startIcon = ImageProvider(appIconRes),
                        title = if (size.width >= 240.dp) appName else "",
                        iconColor = GlanceTheme.colors.primary,
                        actions = {
                            PillButton(featured, filled, GlanceModifier.padding(end = WidgetPadding))
                        },
                    )
                },
            ) {
                TwoRowGrid(buttonItems, GlanceModifier.fillMaxSize())
            }
        }
        else -> {
            Scaffold(modifier = GlanceModifier.padding(vertical = WidgetPadding), backgroundColor = Transparent, horizontalPadding = WidgetPadding) {
                val regular = buttonItems.take(if (size.width >= 240.dp) 4 else 2)
                TwoRowGrid(listOf(appIcon, featuredItem) + regular, GlanceModifier.fillMaxSize())
            }
        }
    }
}

@Composable
private fun FluidAppIcon(@DrawableRes iconRes: Int) {
    Box(modifier = GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Image(
            provider = ImageProvider(iconRes),
            contentDescription = null,
            modifier = GlanceModifier.size(IconSize),
            colorFilter = ColorFilter.tint(GlanceTheme.colors.onSurface),
        )
    }
}

@Composable
private fun FluidFeaturedButton(button: WidgetButton, filled: Boolean) {
    IconButton(
        button = button,
        containerColor = if (filled) GlanceTheme.colors.tertiary else Transparent,
        contentColor = if (filled) GlanceTheme.colors.onTertiary else GlanceTheme.colors.onSecondaryContainer,
        cornerRadius = CornerFull,
        modifier = GlanceModifier.fillMaxSize(),
    )
}

@Composable
private fun FluidButton(button: WidgetButton, filled: Boolean) {
    IconButton(
        button = button,
        containerColor = if (filled) GlanceTheme.colors.secondaryContainer else Transparent,
        contentColor = GlanceTheme.colors.onSecondaryContainer,
        cornerRadius = CornerMedium,
        modifier = GlanceModifier.fillMaxSize(),
    )
}

/** The featured action in the title bar: a 52x32 dp pill in a 48 dp tall tap target. */
@Composable
private fun PillButton(button: WidgetButton, filled: Boolean, modifier: GlanceModifier) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .semantics { contentDescription = button.contentDescription }
            .height(MinButtonSize)
            .clickable(button.onClick),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = GlanceModifier
                .width(52.dp)
                .height(32.dp)
                .background(if (filled) GlanceTheme.colors.tertiary else Transparent)
                .cornerRadius(CornerFull),
        ) {
            Image(
                provider = ImageProvider(button.iconRes),
                contentDescription = null,
                colorFilter = ColorFilter.tint(GlanceTheme.colors.onTertiary),
                modifier = GlanceModifier.size(IconSize),
            )
        }
    }
}

@Composable
private fun IconButton(
    button: WidgetButton,
    containerColor: ColorProvider,
    contentColor: ColorProvider,
    cornerRadius: Dp,
    modifier: GlanceModifier,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .background(containerColor)
            .cornerRadius(cornerRadius)
            .semantics { contentDescription = button.contentDescription }
            .clickable(button.onClick),
    ) {
        Image(
            provider = ImageProvider(button.iconRes),
            contentDescription = null,
            colorFilter = ColorFilter.tint(contentColor),
            modifier = GlanceModifier.size(IconSize),
        )
    }
}

/** Items in one row, equally wide, [ItemSpacing] apart. */
@Composable
private fun SpacedRow(items: List<@Composable () -> Unit>, modifier: GlanceModifier) {
    Row(modifier = modifier) {
        items.forEachIndexed { index, item ->
            Box(modifier = GlanceModifier.padding(start = if (index == 0) 0.dp else ItemSpacing).fillMaxHeight().defaultWeight()) {
                item()
            }
        }
    }
}

/** Items in one column, equally tall, [ItemSpacing] apart. */
@Composable
private fun SpacedColumn(items: List<@Composable () -> Unit>, modifier: GlanceModifier) {
    Column(modifier = modifier) {
        items.forEachIndexed { index, item ->
            Box(modifier = GlanceModifier.padding(top = if (index == 0) 0.dp else ItemSpacing).fillMaxWidth().defaultWeight()) {
                item()
            }
        }
    }
}

/** The first half of [items] in the top row, the rest below. */
@Composable
private fun TwoRowGrid(items: List<@Composable () -> Unit>, modifier: GlanceModifier) {
    val middle = (items.size + 1) / 2
    Column(modifier = modifier) {
        SpacedRow(items.subList(0, middle), GlanceModifier.fillMaxWidth().defaultWeight())
        Spacer(modifier = GlanceModifier.height(ItemSpacing))
        SpacedRow(items.subList(middle, items.size), GlanceModifier.fillMaxWidth().defaultWeight())
    }
}

/** The one-row bar's height: Material 3's toolbar height, 48 dp targets and 8 dp around them. */
private val CompactBarHeight = 64.dp
private val CompactBarPadding = 8.dp

/** Accessible tap target. */
private val MinButtonSize = 48.dp
private val WidgetPadding = 12.dp
private val ItemSpacing = 8.dp
private val IconSize = 24.dp
/** M3 shape tokens: medium for the regular actions, full for the featured one. */
private val CornerMedium = 16.dp
private val CornerFull = 100.dp

/**
 * The header and the 2x2 grid together: a 48 dp title bar, two 48 dp rows with
 * the spacing between them and the bottom padding. Google's reference waits
 * for 172 dp; this is the height at which everything fits with full tap
 * targets, so a 2x2 widget on a four-column home screen shows all actions.
 */
private val HeaderGridMinHeight = MinButtonSize * 3 + ItemSpacing + WidgetPadding

private val Transparent = androidx.glance.color.ColorProvider(Color.Transparent, Color.Transparent)
