package com.airbridge.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope.SlideDirection
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
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
import com.airbridge.protocol.FileEntry
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Browser for the Mac's home directory. Renders as plain content inside the
 * shared [MainActivity] Scaffold — it does NOT create its own Scaffold (that
 * would double the insets and collide with the global FAB). The upload action
 * lives on the host's contextual FAB. [bottomClearance] keeps the list above
 * that FAB and the dock.
 *
 * Interaction is deliberately minimal: tapping a folder opens it, tapping a file
 * downloads it (a small progress ring shows while it transfers; completion is
 * confirmed by the system "file received" notification). Downloads are
 * serialized one-at-a-time under the hood.
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
    // Per-file download progress (filename -> 0..1). A row shows a small progress
    // ring while its name is present here (queued files sit at 0 until their turn).
    val downloadProgress by viewModel.macDownloadProgress.collectAsState()

    // Load the root listing the first time the tab is shown and we are connected.
    // Guard on path and entries being empty so a reconnect while browsing a subfolder
    // does NOT reset navigation back to root.
    LaunchedEffect(isConnected) {
        if (isConnected && path.isEmpty() && entries.isEmpty()) {
            viewModel.openMacFolder("")
        }
    }

    // Briefly flag a file as "just downloaded" when it leaves the progress map having
    // succeeded — the row's progress ring then pops into a check for ~1.5s before
    // clearing (the lasting confirmation is the system "file received" notification).
    val downloadedNames by viewModel.macDownloadedNames.collectAsState()
    val scope = rememberCoroutineScope()
    val justDone = remember { mutableStateListOf<String>() }
    LaunchedEffect(Unit) {
        var prev = emptySet<String>()
        snapshotFlow { downloadProgress.keys.toSet() }.collect { current ->
            (prev - current).forEach { name ->
                if (name in downloadedNames && name !in justDone) {
                    justDone.add(name)
                    scope.launch { delay(1500); justDone.remove(name) }
                }
            }
            prev = current
        }
    }

    // Cache each folder's last-known listing. Every navigation clears entries and refetches
    // from the Mac, so without this, going back (or re-entering a folder) would slide into an
    // empty pane that then reloads. With the cache we show real content immediately and the
    // background refresh updates it in place — making the back slide a true push.
    val folderCache = remember { mutableStateMapOf<String, List<FileEntry>>() }
    LaunchedEffect(path, entries) {
        if (entries.isNotEmpty()) folderCache[path] = entries
    }
    val effectiveEntries = if (entries.isNotEmpty()) entries else folderCache[path] ?: emptyList()

    // Navigate optimistically: the slide starts the instant a folder is tapped. Forward
    // re-entry and going back push real content (from the cache); a never-seen folder fills
    // in during the ~330ms slide, or shows a delayed spinner if the listing is genuinely slow.
    var displayed by remember { mutableStateOf(FolderPage(path, effectiveEntries, needsPermission)) }
    LaunchedEffect(path, effectiveEntries, loading, needsPermission) {
        displayed = FolderPage(path, effectiveEntries, needsPermission)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Breadcrumb path bar — tappable segments, each jumps straight to that
        // ancestor (mirror of the macOS FilesBrowserView path bar).
        if (isConnected) {
            MacPathBar(path = path, onNavigate = { viewModel.openMacFolder(it) })
        }

        // Directional folder navigation: entering a folder pushes the new listing in
        // from the right, going up slides it back from the left (by path depth).
        AnimatedContent(
            targetState = displayed,
            modifier = Modifier.fillMaxSize(),
            transitionSpec = {
                if (initialState.path == targetState.path) {
                    // Same folder (content refresh) — swap instantly, no slide.
                    (fadeIn(snap()) togetherWith fadeOut(snap())) using null
                } else {
                    val dir = if (folderDepth(targetState.path) >= folderDepth(initialState.path))
                        SlideDirection.Left else SlideDirection.Right
                    (slideIntoContainer(dir, tween(330, easing = FastOutSlowInEasing)) + fadeIn(tween(220))) togetherWith
                        (slideOutOfContainer(dir, tween(300, easing = FastOutSlowInEasing)) + fadeOut(tween(200)))
                }
            },
            label = "folderNav"
        ) { page ->
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

            page.needsPermission -> {
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

            page.entries.isEmpty() && loading -> {
                // Listing still arriving. Reveal a spinner only if it is genuinely slow —
                // on a fast load the content lands during the slide and we never flash one.
                var showSpinner by remember { mutableStateOf(false) }
                LaunchedEffect(Unit) { delay(200); showSpinner = true }
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    if (showSpinner) CircularProgressIndicator()
                }
            }

            page.entries.isEmpty() -> {
                // Folder genuinely has no files or subfolders — say so explicitly,
                // otherwise a blank screen reads like a failure.
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(R.string.mac_files_empty_folder),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            else -> {
                val listState = rememberLazyListState()
                ScrollLimitHaptics(listState)
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = bottomClearance)
                ) {
                    itemsIndexed(page.entries, key = { _, it -> it.relativePath }) { index, entry ->
                        val thumb = thumbs[entry.relativePath]
                        val downloading = !entry.isDirectory && entry.name in downloadProgress
                        // Grouped-list shape: the first/last rows round their outer edges
                        // strongly, rows between are gently rounded. With a small gap the list
                        // reads as one rounded group (M3 Expressive style).
                        val isFirst = index == 0
                        val isLast = index == page.entries.lastIndex
                        val shape = RoundedCornerShape(
                            topStart = if (isFirst) 20.dp else 8.dp,
                            topEnd = if (isFirst) 20.dp else 8.dp,
                            bottomStart = if (isLast) 20.dp else 8.dp,
                            bottomEnd = if (isLast) 20.dp else 8.dp
                        )

                        // Request a thumbnail for media files on appearance — but only if we
                        // don't already have it cached (thumbnails persist across navigation),
                        // so returning to a folder doesn't re-fetch. Folder stats are
                        // intentionally NOT requested in v1 (not displayed, and the recursive
                        // size walk per folder froze the Mac on large trees).
                        LaunchedEffect(entry.relativePath) {
                            if (thumb == null && !entry.isDirectory &&
                                (entry.mimeType.startsWith("image/") || entry.mimeType.startsWith("video/"))
                            ) {
                                viewModel.requestMacThumb(entry.relativePath)
                            }
                        }

                        ListItem(
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
                            // A small progress ring appears while the file transfers, then
                            // pops into a check for a moment on completion; otherwise the row
                            // has no trailing control — tapping the row is the download action.
                            trailingContent = if (downloading || entry.name in justDone) {
                                {
                                    AnimatedContent(
                                        targetState = downloading,
                                        contentAlignment = Alignment.Center,
                                        transitionSpec = {
                                            // The check springs in; the ring just fades out.
                                            (fadeIn(tween(150)) + scaleIn(
                                                initialScale = 0.5f,
                                                animationSpec = spring(
                                                    dampingRatio = Spring.DampingRatioMediumBouncy,
                                                    stiffness = Spring.StiffnessMediumLow
                                                )
                                            )) togetherWith fadeOut(tween(120)) using null
                                        },
                                        label = "downloadTrailing"
                                    ) { isDownloading ->
                                        if (isDownloading) {
                                            CircularProgressIndicator(
                                                progress = { (downloadProgress[entry.name] ?: 0f).coerceIn(0f, 1f) },
                                                modifier = Modifier.size(22.dp),
                                                strokeWidth = 2.dp
                                            )
                                        } else {
                                            Icon(
                                                imageVector = Icons.Rounded.CheckCircle,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.size(24.dp)
                                            )
                                        }
                                    }
                                }
                            } else null,
                            // Tap a folder to open it; tap a file to download it. A file
                            // already transferring is not re-tappable. The shape morphs on
                            // press (native ListItem shapes).
                            onClick = {
                                if (entry.isDirectory) viewModel.openMacFolder(entry.relativePath)
                                else viewModel.downloadMacFile(entry.relativePath)
                            },
                            enabled = entry.isDirectory || !downloading,
                            shapes = ListItemDefaults.shapes(shape = shape),
                            colors = ListItemDefaults.colors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                            ),
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = entry.name,
                                style = MaterialTheme.typography.bodyLarge,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
        }
    }
}

/** A snapshot of one folder's renderable content, so the slide can keep showing the
 *  previous folder until the next one's listing is ready. */
private data class FolderPage(
    val path: String,
    val entries: List<FileEntry>,
    val needsPermission: Boolean
)

private fun folderDepth(path: String): Int =
    if (path.isEmpty()) 0 else path.split('/').count { it.isNotEmpty() }

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
    bytes < 1024L * 1024L * 1024L -> String.format(java.util.Locale.getDefault(), "%.1f MB", bytes / (1024.0 * 1024.0))
    else -> String.format(java.util.Locale.getDefault(), "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
}
