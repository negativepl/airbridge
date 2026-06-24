package com.airbridge.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.ActivityItem

private const val FEED_LIMIT = 8

@Composable
fun ActivityFeed(items: List<ActivityItem>, modifier: Modifier = Modifier) {
    // Recent activity is about transfers — clipboard syncs fire on every copy and
    // would bury the list in noise, so they are not shown here.
    val transfers = remember(items) {
        items.filter { it.type == "file_sent" || it.type == "file_received" }.take(FEED_LIMIT)
    }
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.recent_activity),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 8.dp)
        )
        if (transfers.isEmpty()) {
            EmptyActivity()
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                transfers.forEach { item -> TransferRow(item) }
            }
        }
    }
}

@Composable
private fun TransferRow(item: ActivityItem) {
    val sent = item.type == "file_sent"
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLowest
    ) {
        ListItem(
            headlineContent = {
                Text(
                    item.description.ifBlank { item.type },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
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
}

@Composable
private fun EmptyActivity() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(MaterialShapes.Flower.toShape())
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Rounded.SwapVert,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(32.dp)
            )
        }
        Spacer(Modifier.height(12.dp))
        Text(
            stringResource(R.string.no_activity),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
