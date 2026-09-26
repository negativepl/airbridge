package com.airbridge.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Card
import androidx.compose.material3.CardColors
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.innerShadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp

/**
 * A one-dp line of light on the top edge of a card, so surfaces read as lit
 * from above instead of flat. Tuned per mode: soft on light surfaces, faint on dark.
 */
@Composable
fun Modifier.edgeLight(shape: Shape): Modifier {
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val highlight = if (dark) Color.White.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.75f)
    return innerShadow(shape, Shadow(radius = 1.dp, color = highlight, offset = DpOffset(0.dp, 1.dp)))
}

/** Material Card with the edge light applied. Same parameters as [Card]. */
@Composable
fun AirbridgeCard(
    modifier: Modifier = Modifier,
    shape: Shape = MaterialTheme.shapes.extraLarge,
    colors: CardColors = CardDefaults.cardColors(),
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(modifier = modifier.edgeLight(shape), shape = shape, colors = colors, content = content)
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

/** Dashed hairline used inside cards instead of a solid border. */
@Composable
fun DashedDivider(modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.outlineVariant) {
    Canvas(modifier = modifier.fillMaxWidth().height(1.dp)) {
        drawLine(
            color = color,
            start = Offset(0f, size.height / 2f),
            end = Offset(size.width, size.height / 2f),
            strokeWidth = size.height,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))
        )
    }
}
