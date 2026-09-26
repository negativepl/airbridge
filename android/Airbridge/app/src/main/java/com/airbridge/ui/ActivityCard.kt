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
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.ActivityItem
import com.airbridge.stats.Stats
import com.airbridge.stats.formatBytes

private const val FEED_LIMIT = 8

/**
 * One "Activity" card: sent and received totals on top (size as the number,
 * file count as the caption), then the recent transfers underneath. Clipboard
 * syncs fire on every copy and would bury the list, so they are not shown.
 */
@Composable
fun ActivityCard(stats: Stats, items: List<ActivityItem>, modifier: Modifier = Modifier) {
    val c = stats.total
    val transfers = remember(items) {
        items.filter { it.type == "file_sent" || it.type == "file_received" }.take(FEED_LIMIT)
    }
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.home_section_activity),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 16.dp, bottom = 8.dp)
        )
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.extraLarge,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                StatColumn(
                    icon = Icons.Rounded.ArrowUpward,
                    value = formatBytes(c.bytesSent),
                    label = stringResource(R.string.stats_sent_row),
                    caption = pluralStringResource(R.plurals.activity_file_count, c.filesSent, c.filesSent),
                    modifier = Modifier.weight(1f)
                )
                StatColumn(
                    icon = Icons.Rounded.ArrowDownward,
                    value = formatBytes(c.bytesReceived),
                    label = stringResource(R.string.stats_received_row),
                    caption = pluralStringResource(R.plurals.activity_file_count, c.filesReceived, c.filesReceived),
                    modifier = Modifier.weight(1f)
                )
            }
            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 20.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )
            if (transfers.isEmpty()) {
                Text(
                    stringResource(R.string.no_activity),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 18.dp)
                )
            } else {
                transfers.forEachIndexed { index, item ->
                    if (index > 0) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 72.dp, end = 20.dp),
                            color = MaterialTheme.colorScheme.outlineVariant
                        )
                    }
                    TransferRow(item)
                }
            }
        }
    }
}

@Composable
private fun StatColumn(icon: ImageVector, value: String, label: String, caption: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                value,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(Modifier.height(4.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(caption, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun TransferRow(item: ActivityItem) {
    val sent = item.type == "file_sent"
    ListItem(
        content = {
            Text(item.description.ifBlank { item.type }, maxLines = 1, overflow = TextOverflow.Ellipsis)
        },
        supportingContent = {
            Text(stringResource(if (sent) R.string.activity_sent else R.string.activity_received))
        },
        leadingContent = {
            val container = if (sent) MaterialTheme.colorScheme.primaryContainer
                            else MaterialTheme.colorScheme.tertiaryContainer
            val onContainer = if (sent) MaterialTheme.colorScheme.onPrimaryContainer
                              else MaterialTheme.colorScheme.onTertiaryContainer
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(MaterialShapes.Cookie7Sided.toShape())
                    .background(container),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    if (sent) Icons.Rounded.Upload else Icons.Rounded.Download,
                    contentDescription = null,
                    tint = onContainer,
                    modifier = Modifier.size(22.dp)
                )
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    )
}
