package com.airbridge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.stats.StatCounters
import com.airbridge.stats.Stats
import com.airbridge.stats.formatBytes
import com.airbridge.stats.formatDuration

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
        val cells = listOf(
            Triple(Icons.Rounded.Upload, "${c.filesSent}", R.string.stats_files_sent),
            Triple(Icons.Rounded.Upload, formatBytes(c.bytesSent), R.string.stats_data_sent),
            Triple(Icons.Rounded.Download, "${c.filesReceived}", R.string.stats_files_received),
            Triple(Icons.Rounded.Download, formatBytes(c.bytesReceived), R.string.stats_data_received),
            Triple(Icons.Rounded.ContentCopy, "${c.clipboardSyncs}", R.string.stats_clipboard),
            Triple(Icons.Rounded.Schedule, formatDuration(c.connectedSeconds), R.string.stats_online),
        )
        cells.chunked(2).forEach { rowCells ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                rowCells.forEach { (icon, value, labelRes) ->
                    StatCard(icon, value, stringResource(labelRes), Modifier.weight(1f))
                }
                if (rowCells.size == 1) Spacer(Modifier.weight(1f))
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun StatCard(icon: androidx.compose.ui.graphics.vector.ImageVector, value: String, label: String, modifier: Modifier) {
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Column(Modifier.padding(16.dp)) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(8.dp))
            Text(value, style = MaterialTheme.typography.headlineMedium)
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
