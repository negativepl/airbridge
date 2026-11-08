package com.airbridge.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.material3.MotionScheme
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.ScreenShare
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FabPosition
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.material3.ToggleFloatingActionButtonDefaults.animateIcon
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.airbridge.R
import java.util.Locale

/**
 * The main tabs: Home, Screen sharing and Mac Files, switched with a fade-through under one shared
 * top bar, with the bottom navigation bar, the send FAB menu and the send
 * confirmation sheet. Settings and the QR scanner are pushed by the caller.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TabsScreen(viewModel: MainViewModel, onOpenSettings: () -> Unit, onScanQr: () -> Unit) {
    data class NavItem(
        val labelRes: Int,
        val icon: ImageVector
    )

    // Dolny pasek: tylko miejsca główne. Ustawienia i O aplikacji
    // przeniesione do górnego paska.
    val navItems = listOf(
        NavItem(R.string.nav_home, Icons.Rounded.Home),
        NavItem(R.string.nav_screen_sharing, Icons.AutoMirrored.Rounded.ScreenShare),
        NavItem(R.string.nav_mac_files, Icons.Rounded.Folder)
    )
    // Tytuł w górnym pasku: pełna nazwa miejsca, dok ma krótsze etykiety.
    val pageTitles = listOf(
        R.string.app_name,
        R.string.page_screen_sharing,
        R.string.page_mac_files
    )

    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    val tabStateHolder = rememberSaveableStateHolder()
    // One top bar state per tab: the bar shows the scrolled
    // colour for the tab on screen, not for whatever tab scrolled last.
    val topBarStates = listOf(
        rememberTopAppBarState(),
        rememberTopAppBarState(),
        rememberTopAppBarState(),
    )
    val topBarBehaviors = listOf(
        TopAppBarDefaults.pinnedScrollBehavior(topBarStates[0]),
        TopAppBarDefaults.pinnedScrollBehavior(topBarStates[1]),
        TopAppBarDefaults.pinnedScrollBehavior(topBarStates[2]),
    )
    val context = LocalContext.current
    val pairedDeviceStore = remember { com.airbridge.security.PairedDeviceStore(context) }
    val pairedDevicesRevision by com.airbridge.security.PairedDeviceStore.revision.collectAsState()
    val hasPairedDevices = remember(pairedDevicesRevision) {
        pairedDeviceStore.getAll().isNotEmpty()
    }
    var fabMenuExpanded by remember { mutableStateOf(false) }
    var pendingFileUri by remember { mutableStateOf<Uri?>(null) }
    var pendingIsPhoto by remember { mutableStateOf(false) }
    val haptic = LocalHapticFeedback.current
    // Resolved in composition so they follow locale changes; the Toasts
    // below fire from click callbacks where stringResource() can't be called.
    val sentToMacMsg = stringResource(R.string.sent_to_mac)
    val clipboardEmptyMsg = stringResource(R.string.clipboard_empty)

    // Bottom clearance for the tab content: the FAB (56 dp) plus its 16 dp
    // margin above the dock plus the same 16 dp gap above the FAB, so the
    // last row sits as far above the FAB as the FAB sits above the dock.
    val fabClearance = 88.dp

    val macFilesPath by viewModel.macFilesPath.collectAsState()
    // Each folder pane in Mac Files starts a fresh list at the top, so
    // the tab's top bar state must forget the previous folder's offset.
    LaunchedEffect(macFilesPath) { topBarStates[2].contentOffset = 0f }
    // Pickers. On the Files tab a chosen file/photo uploads straight into the
    // folder currently open on the Mac; elsewhere it goes through the
    // confirmation flow (pendingFileUri) to the Mac's default location. Same
    // FAB on every tab — only the destination differs, decided here.
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let {
            if (selectedTab == 2) {
                viewModel.uploadToMac(it, macFilesPath)
            } else {
                pendingFileUri = it
                pendingIsPhoto = false
            }
        }
    }
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let {
            if (selectedTab == 2) {
                viewModel.uploadToMac(it, macFilesPath)
            } else {
                pendingFileUri = it
                pendingIsPhoto = true
            }
        }
    }
    // On the Files tab, Back walks up the Mac folder tree instead of
    // leaving the app. Gated on the tab being current AND being in a
    // subfolder, so it never hijacks Back on other screens or at root.
    BackHandler(enabled = selectedTab == 2 && macFilesPath.isNotEmpty()) {
        viewModel.openMacFolder(macFilesPath.substringBeforeLast('/', ""))
    }

    // FAB menu action bodies, extracted so the menu items stay thin.
    val sendFileAction = { filePickerLauncher.launch(arrayOf("*/*")) }
    val sendPhotoAction = {
        photoPickerLauncher.launch(
            androidx.activity.result.PickVisualMediaRequest(
                ActivityResultContracts.PickVisualMedia.ImageAndVideo
            )
        )
    }
    val sendClipboardAction = {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip
        val text = if (clip != null && clip.itemCount > 0)
            clip.getItemAt(0).coerceToText(context).toString() else ""
        if (text.isNotEmpty()) {
            viewModel.sendClipboard(text)
            Toast.makeText(context, sentToMacMsg, Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(context, clipboardEmptyMsg, Toast.LENGTH_SHORT).show()
        }
    }

    // One shared top bar above the tabs; each tab owns the scroll state that colours it.
    Scaffold(
        containerColor = MaterialTheme.colorScheme.pageBackground,
        bottomBar = {
            // Short Material 3 Expressive navigation bar, one container step off the page.
            ShortNavigationBar(
                containerColor = MaterialTheme.colorScheme.dockContainer,
            ) {
                navItems.forEachIndexed { index, item ->
                    ShortNavigationBarItem(
                        selected = selectedTab == index,
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            selectedTab = index
                        },
                        icon = {
                            Icon(
                                item.icon,
                                contentDescription = stringResource(item.labelRes)
                            )
                        },
                        label = { Text(stringResource(item.labelRes)) }
                    )
                }
            }
        },
        floatingActionButton = {
            if (hasPairedDevices) {
                BackHandler(fabMenuExpanded) { fabMenuExpanded = false }
                FloatingActionButtonMenu(
                    expanded = fabMenuExpanded,
                    horizontalAlignment = Alignment.End,
                    button = {
                        ToggleFloatingActionButton(
                            checked = fabMenuExpanded,
                            onCheckedChange = { fabMenuExpanded = it },
                        ) {
                            val showingClose by remember {
                                derivedStateOf { checkedProgress > 0.5f }
                            }
                            val icon = if (showingClose) Icons.Rounded.Close else Icons.Rounded.FileUpload
                            Icon(
                                painter = rememberVectorPainter(icon),
                                contentDescription = stringResource(
                                    if (showingClose) R.string.fab_close_menu else R.string.nav_send
                                ),
                                modifier = Modifier.animateIcon({ checkedProgress })
                            )
                        }
                    }
                ) {
                    // Identical FAB on every tab — same three actions. The send
                    // destination (current Mac folder vs default) is decided in
                    // the picker callbacks above, so the menu never swaps items
                    // between tabs and the tab switch stays smooth.
                    FloatingActionButtonMenuItem(
                        onClick = {
                            fabMenuExpanded = false
                            sendFileAction()
                        },
                        icon = { Icon(Icons.AutoMirrored.Rounded.InsertDriveFile, contentDescription = null) },
                        text = { Text(stringResource(R.string.action_send_file)) }
                    )
                    FloatingActionButtonMenuItem(
                        onClick = {
                            fabMenuExpanded = false
                            sendPhotoAction()
                        },
                        icon = { Icon(Icons.Rounded.Photo, contentDescription = null) },
                        text = { Text(stringResource(R.string.action_send_photo)) }
                    )
                    FloatingActionButtonMenuItem(
                        onClick = {
                            fabMenuExpanded = false
                            sendClipboardAction()
                        },
                        icon = { Icon(Icons.Rounded.ContentPaste, contentDescription = null) },
                        text = { Text(stringResource(R.string.action_send_clipboard)) }
                    )
                }
            }
        },
        floatingActionButtonPosition = FabPosition.End
    ) { innerPadding ->
        // The bar sits above the tabs (not in the Scaffold) so the tabs can
        // reserve its height themselves and report their scroll to their own
        // top bar state.
        // Tabs run under both bars (no Scaffold padding); each tab
        // reserves the top bar height and the dock height plus the FAB
        // clearance itself, and the bars are opaque.
        val pageBottomClearance = fabClearance + innerPadding.calculateBottomPadding()
        val topInset = TopAppBarDefaults.TopAppBarExpandedHeight +
            WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
        Box(modifier = Modifier.fillMaxSize()) {
            val tabEnterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
            val tabEnterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
            val tabExitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
            AnimatedContent(
                targetState = selectedTab,
                transitionSpec = {
                    // Fade through: the old tab fades out, the new one fades in while
                    // settling from 92 % to full size.
                    (fadeIn(tabEnterFade) + scaleIn(initialScale = 0.92f, animationSpec = tabEnterScale)) togetherWith
                        fadeOut(tabExitFade)
                },
                contentAlignment = Alignment.Center,
                label = "tab"
            ) { tab ->
                // Saves each tab's scroll position while it is off screen so it matches the tab's top bar state on return.
                tabStateHolder.SaveableStateProvider(tab) {
                    // Each tab reports its scroll to its own top bar state.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .nestedScroll(topBarBehaviors[tab].nestedScrollConnection)
                    ) {
                        when (tab) {
                            0 -> MainScreen(
                                viewModel = viewModel,
                                onScanQr = onScanQr,
                                bottomClearance = pageBottomClearance,
                                topInset = topInset,
                                onSendFile = sendFileAction,
                                onSendPhoto = sendPhotoAction,
                                onSendClipboard = sendClipboardAction
                            )
                            1 -> ScreenShareScreen(bottomClearance = pageBottomClearance, topInset = topInset)
                            2 -> MacFilesScreen(viewModel = viewModel, bottomClearance = pageBottomClearance, topInset = topInset)
                        }
                    }
                }
            }
            // One fixed bar over the tabs, title centred. Inside a Mac folder the
            // bar takes the folder's name as its title, the path above it as the
            // subtitle and an up arrow, the way Google's file browsers do; the
            // settings action stays put throughout.
            val folderSegments = remember(macFilesPath) { macFilesPath.split('/').filter { it.isNotEmpty() } }
            val inFolder = selectedTab == 2 && folderSegments.isNotEmpty()
            val header = BarHeader(
                tab = selectedTab,
                path = if (selectedTab == 2) macFilesPath else "",
                title = if (inFolder) folderSegments.last() else stringResource(pageTitles[selectedTab]),
                subtitle = if (inFolder) {
                    (listOf(stringResource(R.string.mac_files_root)) + folderSegments.dropLast(1)).joinToString(" / ")
                } else null
            )
            // The header moves with the page under it, using the same M3 transition
            // pattern and the same specs, so bar and page read as one motion:
            // - another tab: fade through, like the tab content;
            // - another Mac folder: shared axis X in the direction of the folder
            //   pane (deeper enters from the right, up from the left), on the same
            //   spatial spring as the listing.
            // Title and path are one block, so they never change on separate beats.
            val folderSpatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
            val folderEffects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
            // The arrow's width uses the standard (non-bouncy) spring: an overshoot
            // would push the title past its resting place and back.
            val arrowWidth = MotionScheme.standard().defaultSpatialSpec<IntSize>()
            TopAppBar(
                title = {
                    AnimatedContent(
                        targetState = header,
                        transitionSpec = {
                            if (initialState.tab != targetState.tab) {
                                (fadeIn(tabEnterFade) + scaleIn(
                                    initialScale = 0.92f,
                                    transformOrigin = TransformOrigin(0f, 0.5f),
                                    animationSpec = tabEnterScale
                                )) togetherWith fadeOut(tabExitFade) using SizeTransform(clip = false)
                            } else {
                                val deeper = folderDepth(targetState.path) >= folderDepth(initialState.path)
                                val sign = if (deeper) 1 else -1
                                (slideInHorizontally(folderSpatial) { sign * it / 4 } + fadeIn(folderEffects)) togetherWith
                                    (slideOutHorizontally(folderSpatial) { -sign * it / 4 } + fadeOut(tabExitFade)) using
                                    SizeTransform(clip = false)
                            }
                        },
                        contentAlignment = Alignment.CenterStart,
                        label = "pageHeader"
                    ) { h ->
                        Column {
                            Text(
                                h.title,
                                color = MaterialTheme.colorScheme.pageTitleColor,
                                fontWeight = FontWeight(450),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (h.subtitle != null) {
                                Text(
                                    h.subtitle,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                },
                // The path is part of the title block above; the overload that takes
                // titleHorizontalAlignment also requires this slot.
                subtitle = {},
                navigationIcon = {
                    // Grows from the start edge so the title glides aside instead of jumping.
                    AnimatedVisibility(
                        visible = inFolder,
                        enter = expandHorizontally(arrowWidth, expandFrom = Alignment.Start) + fadeIn(folderEffects),
                        exit = shrinkHorizontally(arrowWidth, shrinkTowards = Alignment.Start) + fadeOut(tabExitFade)
                    ) {
                        IconButton(onClick = { viewModel.openMacFolder(macFilesPath.substringBeforeLast('/', "")) }) {
                            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                        }
                    }
                },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Rounded.Settings, contentDescription = stringResource(R.string.nav_settings))
                    }
                },
                titleHorizontalAlignment = Alignment.Start,
                // The bar stays the page colour under scrolled content, as in Google One.
                colors = pageTopAppBarColors(tintWhenScrolled = false),
                scrollBehavior = topBarBehaviors[selectedTab],
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }
    }

    // File/photo confirmation sheet
    if (pendingFileUri != null) {
        val sheetState = rememberBottomSheetState(
            SheetValue.Hidden,
            setOf(SheetValue.Hidden, SheetValue.Expanded)
        )
        ModalBottomSheet(
            onDismissRequest = { pendingFileUri = null },
            sheetState = sheetState
        ) {
            SendConfirmationSheet(
                uri = pendingFileUri!!,
                isPhoto = pendingIsPhoto,
                onConfirm = {
                    viewModel.sendFile(pendingFileUri!!)
                    Toast.makeText(context, sentToMacMsg, Toast.LENGTH_SHORT).show()
                    pendingFileUri = null
                },
                onCancel = { pendingFileUri = null }
            )
        }
    }
}

@Composable
private fun SendConfirmationSheet(
    uri: Uri,
    isPhoto: Boolean,
    onConfirm: () -> Unit,
    onCancel: () -> Unit
) {
    val context = LocalContext.current

    // Get file info
    val (fileName, fileSize) = remember(uri) {
        var name = "file"
        var size = 0L
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: "file"
                val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIdx >= 0) size = cursor.getLong(sizeIdx)
            }
        }
        name to size
    }

    val sizeText = remember(fileSize) {
        when {
            fileSize < 1024 -> "$fileSize B"
            fileSize < 1024 * 1024 -> "${fileSize / 1024} KB"
            else -> String.format(Locale.getDefault(), "%.1f MB", fileSize / (1024.0 * 1024.0))
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 8.dp)
    ) {
        Text(
            text = stringResource(R.string.send_confirm_title),
            style = MaterialTheme.typography.titleLargeEmphasized,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(20.dp))

        // Photo preview or file icon
        if (isPhoto) {
            AsyncImage(
                model = uri,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp)
                    .clip(MaterialTheme.shapes.large),
                contentScale = ContentScale.Crop
            )
            Spacer(modifier = Modifier.height(16.dp))
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.large)
                    .background(MaterialTheme.colorScheme.surfaceContainer)
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.InsertDriveFile,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(24.dp)
                    )
                }
                Spacer(modifier = Modifier.width(16.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = fileName,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = stringResource(R.string.send_confirm_size, sizeText),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(modifier = Modifier.height(16.dp))
        }

        // File name + size for photos too
        if (isPhoto) {
            Text(
                text = fileName,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = stringResource(R.string.send_confirm_size, sizeText),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
        }

        // Buttons
        Button(
            onClick = onConfirm,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            Icon(
                Icons.Rounded.FileUpload,
                contentDescription = null,
                modifier = Modifier.size(18.dp)
            )
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.send_confirm_button))
        }

        Spacer(modifier = Modifier.height(8.dp))

        OutlinedButton(
            onClick = onCancel,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            Text(stringResource(R.string.send_confirm_cancel))
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

/** What the shared top bar shows: the tab, the Mac folder on the Files tab, and their labels. */
private data class BarHeader(val tab: Int, val path: String, val title: String, val subtitle: String?)
