package com.airbridge.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.Image
import com.airbridge.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MacFilesScreen(viewModel: MainViewModel) {
    val path by viewModel.macFilesPath.collectAsState()
    val entries by viewModel.macFilesEntries.collectAsState()
    val needsPermission by viewModel.macFilesNeedsPermission.collectAsState()
    val loading by viewModel.macFilesLoading.collectAsState()
    val thumbs by viewModel.macFilesThumbnails.collectAsState()
    val isConnected by viewModel.isConnected.collectAsState()

    // Load the root listing the first time the tab is shown and we are connected.
    LaunchedEffect(isConnected) {
        if (isConnected) {
            viewModel.openMacFolder("")
        }
    }

    val pickFile = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        uri?.let { viewModel.uploadToMac(it, path) }
    }

    Scaffold(
        floatingActionButton = {
            if (isConnected) {
                ExtendedFloatingActionButton(
                    onClick = { pickFile.launch(arrayOf("*/*")) },
                    icon = { Icon(Icons.Rounded.Upload, contentDescription = null) },
                    text = { Text(stringResource(R.string.mac_files_upload)) }
                )
            }
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding)) {
            // Breadcrumb / up navigation
            if (path.isNotEmpty()) {
                TextButton(
                    onClick = {
                        val parent = path.substringBeforeLast('/', "")
                        viewModel.openMacFolder(parent)
                    }
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = stringResource(R.string.nav_back),
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "  /$path",
                        style = MaterialTheme.typography.labelLarge
                    )
                }
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
                        CircularProgressIndicator()
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
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(entries, key = { it.relativePath }) { entry ->
                            // Request thumbnails / folder stats on appearance.
                            LaunchedEffect(entry.relativePath) {
                                if (entry.isDirectory) {
                                    viewModel.requestMacStats(entry.relativePath)
                                } else if (entry.mimeType.startsWith("image/") ||
                                    entry.mimeType.startsWith("video/")
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
                                                contentDescription = stringResource(R.string.action_send_file)
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
