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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
    // Tylko licznik łączny — przełącznik Dziś/Łącznie usunięty (decyzja UX).
    val c: StatCounters = stats.total

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.stats_title),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 16.dp, bottom = 8.dp)
        )

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
        content = { Text(stringResource(labelRes), style = MaterialTheme.typography.bodyLarge) },
        trailingContent = {
            Text(
                pluralStringResource(R.plurals.stats_row_value_files, files, files, formatBytes(bytes)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    )
}
