package com.airbridge.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Card
import androidx.compose.material3.CardColors
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.innerShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeInput
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.blur.HazeBlurStyle
import dev.chrisbanes.haze.blur.HazeColorEffect
import dev.chrisbanes.haze.blur.hazeBlur

/**
 * Hairline and light-line colours for the edge light. Dark surfaces sit on an
 * equally dark background, so the tonal outlineVariant vanishes there; a faint
 * white does the job on both the card edge and the dock.
 */
@Composable
private fun edgeLightColors(): Pair<Color, Color> {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    return if (dark) {
        Color.White.copy(alpha = 0.22f) to Color.White.copy(alpha = 0.16f)
    } else {
        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f) to Color.White.copy(alpha = 0.55f)
    }
}

/**
 * Card surface treatment: a faint hairline border around the card plus a
 * one-dp line of light on the top edge, so surfaces read as lit from above
 * instead of flat. Kept dim on purpose: it should be felt, not seen.
 */
@Composable
fun Modifier.edgeLight(shape: Shape, highlight: Boolean = true): Modifier {
    val (outline, light) = edgeLightColors()
    val bordered = this.border(width = 0.75.dp, color = outline, shape = shape)
    // The light line reads as a white streak on a photo, so image cards skip it.
    return if (highlight) {
        bordered.innerShadow(shape, Shadow(radius = 1.dp, color = light, offset = DpOffset(0.dp, 1.dp)))
    } else bordered
}

/**
 * The card's edge light for a full-width bar (the dock): a hairline along the
 * top edge and the same line of light right under it, nothing on the sides.
 */
@Composable
fun Modifier.topEdgeLight(): Modifier {
    val (outline, highlight) = edgeLightColors()
    return this.drawWithContent {
        drawContent()
        val hairline = 0.75.dp.toPx()
        drawRect(color = outline, size = Size(size.width, hairline))
        drawRect(color = highlight, topLeft = Offset(0f, hairline), size = Size(size.width, 1.dp.toPx()))
    }
}

/** Material Card with the edge light applied. Same parameters as [Card]. */
@Composable
fun AirbridgeCard(
    modifier: Modifier = Modifier,
    shape: Shape = MaterialTheme.shapes.extraLarge,
    colors: CardColors = CardDefaults.cardColors(),
    /** False for cards whose top edge is an image. */
    highlight: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(modifier = modifier.edgeLight(shape, highlight), shape = shape, colors = colors, content = content)
}

/** Clickable Material Card with the edge light applied. Same parameters as the clickable [Card]. */
@Composable
fun AirbridgeCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    shape: Shape = MaterialTheme.shapes.extraLarge,
    colors: CardColors = CardDefaults.cardColors(),
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(onClick = onClick, modifier = modifier.edgeLight(shape), shape = shape, colors = colors, content = content)
}

/**
 * Dashed hairline between rows of one card. One physical pixel, short dense
 * dashes, low contrast: it separates without being noticed (the way Medusa's
 * admin UI draws its borders).
 */
@Composable
fun DashedDivider(
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.14f),
) {
    Canvas(modifier = modifier.fillMaxWidth().height(1.dp)) {
        val y = size.height / 2f
        drawLine(
            color = color,
            start = Offset(0f, y),
            end = Offset(size.width, y),
            strokeWidth = 1f,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))
        )
    }
}

/**
 * Glass treatment for a bar the content scrolls under (top bar, dock): the
 * content behind is blurred and tinted with [tint], so sections fade in and
 * out under the bar instead of being cut off by an opaque edge. Where blur
 * is unavailable the bar falls back to the opaque tint.
 */
@Composable
fun Modifier.glassBar(hazeState: HazeState, tint: Color): Modifier {
    val style = HazeBlurStyle {
        blurRadius(24.dp)
        noiseFactor(0f)
        backgroundColor(tint)
        colorEffects(listOf(HazeColorEffect.tint(tint.copy(alpha = 0.72f))))
        fallbackColorEffect(HazeColorEffect.tint(tint))
    }
    return this.hazeBlur(input = HazeInput.Sources(hazeState), style = style)
}
