package com.airbridge.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.ActivityItem

@Composable
fun ActivityFeed(items: List<ActivityItem>, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.recent_activity),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp)
        )
        if (items.isEmpty()) {
            Text(
                stringResource(R.string.no_activity),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, top = 4.dp)
            )
        } else {
            items.forEach { item ->
                ListItem(
                    headlineContent = { Text(item.description.ifBlank { item.type }) },
                    leadingContent = { Icon(iconFor(item.type), contentDescription = null) },
                    trailingContent = {
                        Text(
                            android.text.format.DateUtils
                                .getRelativeTimeSpanString(item.timestamp).toString(),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                )
            }
        }
    }
}

private fun iconFor(type: String) = when (type) {
    "file_sent" -> Icons.Rounded.Upload
    "file_received" -> Icons.Rounded.Download
    "clipboard_sent" -> Icons.Rounded.ContentCopy
    else -> Icons.Rounded.ContentPaste
}
