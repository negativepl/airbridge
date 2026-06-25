package com.airbridge.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.airbridge.R

/**
 * Browser for the Mac's home directory. Renders as plain content inside the
 * shared [MainActivity] Scaffold — it does NOT create its own Scaffold (that
 * would double the insets and collide with the global FAB). The upload action
 * lives on the host's contextual FAB. [bottomClearance] keeps the list above
 * that FAB and the dock.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MacFilesScreen(viewModel: MainViewModel, bottomClearance: Dp = 0.dp) {
    val path by viewModel.macFilesPath.collectAsState()
    val entries by viewModel.macFilesEntries.collectAsState()
    val needsPermission by viewModel.macFilesNeedsPermission.collectAsState()
    val loading by viewModel.macFilesLoading.collectAsState()
    val thumbs by viewModel.macFilesThumbnails.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()

    // Load the root listing the first time the tab is shown and we are connected.
    // Guard on path and entries being empty so a reconnect while browsing a subfolder
    // does NOT reset navigation back to root.
    LaunchedEffect(isConnected) {
        if (isConnected && path.isEmpty() && entries.isEmpty()) {
            viewModel.openMacFolder("")
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Breadcrumb path bar — tappable segments, each jumps straight to that
        // ancestor (mirror of the macOS FilesBrowserView path bar).
        if (isConnected) {
            MacPathBar(path = path, onNavigate = { viewModel.openMacFolder(it) })
        }

        when {
            !isConnected -> {
                // Not connected — show a neutral empty state.
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.not_connected),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            loading && entries.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    LoadingIndicator(modifier = Modifier.size(64.dp))
                }
            }

            needsPermission -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.mac_files_permission_needed),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = bottomClearance)
                ) {
                    items(entries, key = { it.relativePath }) { entry ->
                        // Request a thumbnail for media files on appearance. Folder stats
                        // are intentionally NOT requested in v1: they are not displayed, and
                        // a recursive size walk per folder froze the Mac on large trees.
                        LaunchedEffect(entry.relativePath) {
                            if (!entry.isDirectory &&
                                (entry.mimeType.startsWith("image/") || entry.mimeType.startsWith("video/"))
                            ) {
                                viewModel.requestMacThumb(entry.relativePath)
                            }
                        }

                        val thumb = thumbs[entry.relativePath]

                        ListItem(
                            headlineContent = {
                                Text(
                                    text = entry.name,
                                    style = MaterialTheme.typography.bodyLarge,
                                    maxLines = 1
                                )
                            },
                            supportingContent = if (!entry.isDirectory && entry.size > 0) {
                                {
                                    Text(
                                        text = formatFileSize(entry.size),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            } else null,
                            leadingContent = {
                                if (thumb != null) {
                                    ThumbImage(base64 = thumb)
                                } else {
                                    Icon(
                                        imageVector = if (entry.isDirectory) Icons.Rounded.Folder else Icons.AutoMirrored.Rounded.InsertDriveFile,
                                        contentDescription = null,
                                        tint = if (entry.isDirectory)
                                            MaterialTheme.colorScheme.primary
                                        else
                                            MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(40.dp)
                                    )
                                }
                            },
                            trailingContent = if (!entry.isDirectory) {
                                {
                                    IconButton(
                                        onClick = { viewModel.downloadMacFile(entry.relativePath) }
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Download,
                                            contentDescription = stringResource(R.string.mac_files_download)
                                        )
                                    }
                                }
                            } else null,
                            modifier = Modifier.clickable(enabled = entry.isDirectory) {
                                viewModel.openMacFolder(entry.relativePath)
                            }
                        )
                    }
                }
            }
        }
    }
}

/**
 * Horizontally-scrollable breadcrumb. The root segment is the Mac itself; each
 * path component is tappable and navigates straight to that ancestor. The last
 * segment is the current directory (highlighted, not clickable).
 */
@Composable
private fun MacPathBar(path: String, onNavigate: (String) -> Unit) {
    val segments = remember(path) { path.split('/').filter { it.isNotEmpty() } }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        PathSegment(
            label = stringResource(R.string.mac_files_root),
            isCurrent = segments.isEmpty(),
            onClick = { onNavigate("") }
        )
        segments.forEachIndexed { index, segment ->
            Icon(
                imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp)
            )
            PathSegment(
                label = segment,
                isCurrent = index == segments.lastIndex,
                onClick = { onNavigate(segments.take(index + 1).joinToString("/")) }
            )
        }
    }
}

@Composable
private fun PathSegment(label: String, isCurrent: Boolean, onClick: () -> Unit) {
    Text(
        text = label,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
        color = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 1,
        modifier = Modifier
            .clip(MaterialTheme.shapes.small)
            .clickable(enabled = !isCurrent, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 4.dp)
    )
}

/**
 * Decodes a base64-encoded JPEG/PNG string and renders it as a square thumbnail.
 */
@Composable
private fun ThumbImage(base64: String) {
    val bitmap: Bitmap? = remember(base64) {
        runCatching {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(40.dp)
                .clip(MaterialTheme.shapes.small)
        )
    } else {
        Icon(
            imageVector = Icons.AutoMirrored.Rounded.InsertDriveFile,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(40.dp)
        )
    }
}

private fun formatFileSize(bytes: Long): String = when {
    bytes < 1024L -> "$bytes B"
    bytes < 1024L * 1024L -> "${bytes / 1024} KB"
    bytes < 1024L * 1024L * 1024L -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
    else -> String.format("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
}
