package com.airbridge.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.graphics.shapes.RoundedPolygon
import com.airbridge.R
import com.airbridge.stats.StatCounters
import com.airbridge.stats.Stats
import com.airbridge.stats.formatBytes

/** One transfer metric rendered as an expressive card: a MaterialShapes badge,
 *  an animated count-up value and a label. */
private data class StatSpec(
    val polygon: RoundedPolygon,
    val container: @Composable () -> Color,
    val onContainer: @Composable () -> Color,
    val icon: ImageVector,
    val value: (StatCounters) -> Long,
    val format: (Long) -> String,
    val labelRes: Int,
)

@Composable
fun StatsSection(stats: Stats, modifier: Modifier = Modifier) {
    var showToday by remember { mutableStateOf(false) }
    val c: StatCounters = if (showToday) stats.today else stats.total

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.stats_title),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp)
        )
        val options = listOf(true to R.string.stats_today, false to R.string.stats_total)
        Row(
            modifier = Modifier.fillMaxWidth().selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)
        ) {
            options.forEachIndexed { index, (value, labelRes) ->
                ToggleButton(
                    checked = showToday == value,
                    onCheckedChange = { showToday = value },
                    modifier = Modifier.weight(1f).semantics { role = Role.RadioButton },
                    shapes = if (index == 0) ButtonGroupDefaults.connectedLeadingButtonShapes()
                             else ButtonGroupDefaults.connectedTrailingButtonShapes()
                ) { Text(stringResource(labelRes), maxLines = 1) }
            }
        }
        Spacer(Modifier.height(12.dp))
        // Sent metrics carry primary tones, received metrics tertiary — direction
        // reads from colour at a glance; each card gets a distinct MaterialShape.
        val specs = listOf(
            StatSpec(
                MaterialShapes.Cookie9Sided,
                { MaterialTheme.colorScheme.primaryContainer },
                { MaterialTheme.colorScheme.onPrimaryContainer },
                Icons.Rounded.Upload, { it.filesSent.toLong() }, { it.toString() }, R.string.stats_files_sent
            ),
            StatSpec(
                MaterialShapes.Sunny,
                { MaterialTheme.colorScheme.primaryContainer },
                { MaterialTheme.colorScheme.onPrimaryContainer },
                Icons.Rounded.Upload, { it.bytesSent }, ::formatBytes, R.string.stats_data_sent
            ),
            StatSpec(
                MaterialShapes.Clover4Leaf,
                { MaterialTheme.colorScheme.tertiaryContainer },
                { MaterialTheme.colorScheme.onTertiaryContainer },
                Icons.Rounded.Download, { it.filesReceived.toLong() }, { it.toString() }, R.string.stats_files_received
            ),
            StatSpec(
                MaterialShapes.Flower,
                { MaterialTheme.colorScheme.tertiaryContainer },
                { MaterialTheme.colorScheme.onTertiaryContainer },
                Icons.Rounded.Download, { it.bytesReceived }, ::formatBytes, R.string.stats_data_received
            ),
        )
        specs.chunked(2).forEach { rowSpecs ->
            // IntrinsicSize.Max + fillMaxHeight → obie karty w rzędzie równają się do
            // wyższej, więc dłuższy podpis nie rozciąga jednej karty względem sąsiada.
            Row(
                Modifier.fillMaxWidth().height(IntrinsicSize.Max),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                rowSpecs.forEach { spec ->
                    StatCard(spec, spec.value(c), Modifier.weight(1f).fillMaxHeight())
                }
                if (rowSpecs.size == 1) Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun StatCard(spec: StatSpec, targetValue: Long, modifier: Modifier) {
    var started by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { started = true }
    val animated by animateFloatAsState(
        targetValue = if (started) targetValue.toFloat() else 0f,
        animationSpec = tween(durationMillis = 700),
        label = "statValue"
    )
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Column(Modifier.padding(16.dp)) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(spec.polygon.toShape())
                    .background(spec.container()),
                contentAlignment = Alignment.Center
            ) {
                Icon(spec.icon, contentDescription = null, tint = spec.onContainer(), modifier = Modifier.size(24.dp))
            }
            Spacer(Modifier.height(12.dp))
            Text(spec.format(animated.toLong()), style = MaterialTheme.typography.headlineMedium)
            Text(
                stringResource(spec.labelRes),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
