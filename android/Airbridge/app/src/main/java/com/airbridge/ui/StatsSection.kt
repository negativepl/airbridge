package com.airbridge.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.stats.StatCounters
import com.airbridge.stats.Stats
import com.airbridge.stats.formatBytes

/** Compact transfer stats card: a Today/Total segmented toggle in the header,
 *  and two rows (sent / received) with file count + human-readable size. */
@Composable
fun StatsSection(stats: Stats, modifier: Modifier = Modifier) {
    var showToday by remember { mutableStateOf(false) }
    val c: StatCounters = if (showToday) stats.today else stats.total
    val options = listOf(true to R.string.stats_today, false to R.string.stats_total)

    Column(modifier = modifier.fillMaxWidth()) {
        // Nagłówek sekcji POZA kartą — ta sama gramatyka co "Ostatnia aktywność",
        // z przełącznikiem Dziś/Łącznie po prawej.
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 4.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                stringResource(R.string.stats_title),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.weight(1f)
            )
            SingleChoiceSegmentedButtonRow {
                options.forEachIndexed { index, (value, labelRes) ->
                    SegmentedButton(
                        selected = showToday == value,
                        onClick = { showToday = value },
                        shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                        // Bez domyslnego ptaszka — sam stan tonalny wystarcza (decyzja UX).
                        icon = {},
                        label = { Text(stringResource(labelRes)) }
                    )
                }
            }
        }

        Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Spacer(Modifier.height(8.dp))
        StatRow(
            icon = Icons.Rounded.ArrowUpward,
            labelRes = R.string.stats_sent_row,
            files = c.filesSent,
            bytes = c.bytesSent
        )
        StatRow(
            icon = Icons.Rounded.ArrowDownward,
            labelRes = R.string.stats_received_row,
            files = c.filesReceived,
            bytes = c.bytesReceived
        )
        Spacer(Modifier.height(8.dp))
    }
    }
}

@Composable
private fun StatRow(icon: androidx.compose.ui.graphics.vector.ImageVector, labelRes: Int, files: Int, bytes: Long) {
    ListItem(
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        leadingContent = {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceContainer),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp)
                )
            }
        },
        headlineContent = { Text(stringResource(labelRes), style = MaterialTheme.typography.bodyLarge) },
        trailingContent = {
            Text(
                pluralStringResource(R.plurals.stats_row_value_files, files, files, formatBytes(bytes)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    )
}
