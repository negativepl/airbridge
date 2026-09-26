package com.airbridge.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.unit.dp

/**
 * Horizontal battery glyph, the way the iOS status bar draws one: an outlined
 * body with a terminal on the right and a fill proportional to [percent]. While
 * [charging] a bolt is cut out of the fill so it stays readable at any level.
 * Sized 22 x 11 dp by default; draws in [color] (the current content colour).
 */
@Composable
fun BatteryGlyph(
    percent: Int,
    charging: Boolean,
    modifier: Modifier = Modifier,
    color: Color = LocalContentColor.current,
) {
    Canvas(modifier = modifier.size(width = 22.dp, height = 11.dp)) {
        val stroke = 1.2.dp.toPx()
        val terminalWidth = 1.6.dp.toPx()
        val terminalGap = 0.6.dp.toPx()
        val bodyWidth = size.width - terminalWidth - terminalGap
        val bodyHeight = size.height
        val bodyCorner = CornerRadius(2.6.dp.toPx())
        val inset = stroke + 1.dp.toPx()
        val level = percent.coerceIn(0, 100) / 100f

        drawIntoCanvas { canvas ->
            // A layer lets the bolt clear pixels of the fill and the outline underneath it.
            canvas.saveLayer(Rect(Offset.Zero, size), Paint())

            drawRoundRect(
                color = color,
                topLeft = Offset(stroke / 2f, stroke / 2f),
                size = Size(bodyWidth - stroke, bodyHeight - stroke),
                cornerRadius = bodyCorner,
                style = Stroke(width = stroke),
            )
            val terminalHeight = bodyHeight * 0.42f
            drawRoundRect(
                color = color,
                topLeft = Offset(bodyWidth + terminalGap, (bodyHeight - terminalHeight) / 2f),
                size = Size(terminalWidth, terminalHeight),
                cornerRadius = CornerRadius(0.8.dp.toPx()),
            )
            val fillWidth = (bodyWidth - 2f * inset) * level
            if (fillWidth > 0f) {
                drawRoundRect(
                    color = color,
                    topLeft = Offset(inset, inset),
                    size = Size(fillWidth, bodyHeight - 2f * inset),
                    cornerRadius = CornerRadius(1.2.dp.toPx()),
                )
            }
            if (charging) {
                drawPath(path = boltPath(bodyWidth, bodyHeight), color = Color.Black, blendMode = BlendMode.Clear)
            }

            canvas.restore()
        }
    }
}

/** A small lightning bolt centred in the battery body, about 40% of its width. */
private fun boltPath(bodyWidth: Float, bodyHeight: Float): Path {
    val w = bodyWidth * 0.34f
    val h = bodyHeight * 0.86f
    val left = (bodyWidth - w) / 2f
    val top = (bodyHeight - h) / 2f
    return Path().apply {
        moveTo(left + w * 0.62f, top)
        lineTo(left, top + h * 0.58f)
        lineTo(left + w * 0.46f, top + h * 0.58f)
        lineTo(left + w * 0.38f, top + h)
        lineTo(left + w, top + h * 0.42f)
        lineTo(left + w * 0.54f, top + h * 0.42f)
        close()
    }
}
