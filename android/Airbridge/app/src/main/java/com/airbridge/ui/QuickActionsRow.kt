package com.airbridge.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.ScreenShare
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Spacer
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.R

// Four equal tiles below the device card — same visual language (icons,
// weight) as the FAB menu's three send actions, plus a shortcut to the
// Screen tab. Kept as a single row (not a grid) since there are exactly four.
@Composable
fun QuickActionsRow(
    modifier: Modifier = Modifier,
    onSendFile: () -> Unit = {},
    onSendPhoto: () -> Unit = {},
    onSendClipboard: () -> Unit = {},
    onOpenScreen: () -> Unit = {}
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        QuickActionTile(
            icon = Icons.AutoMirrored.Rounded.InsertDriveFile,
            label = stringResource(R.string.home_action_file),
            onClick = onSendFile,
            modifier = Modifier.weight(1f)
        )
        QuickActionTile(
            icon = Icons.Rounded.Photo,
            label = stringResource(R.string.home_action_photo),
            onClick = onSendPhoto,
            modifier = Modifier.weight(1f)
        )
        QuickActionTile(
            icon = Icons.Rounded.ContentPaste,
            label = stringResource(R.string.home_action_clipboard),
            onClick = onSendClipboard,
            modifier = Modifier.weight(1f)
        )
        QuickActionTile(
            icon = Icons.AutoMirrored.Rounded.ScreenShare,
            label = stringResource(R.string.home_action_screen),
            onClick = onOpenScreen,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun QuickActionTile(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
