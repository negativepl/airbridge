package com.airbridge.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material.icons.rounded.ScreenShare
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FabPosition
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.material3.ShortNavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ToggleFloatingActionButtonDefaults.animateIcon
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.airbridge.R
import java.util.Locale
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    @OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        viewModel.startService()

        setContent {
            val prefs = remember {
                getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE)
            }
            var onboardingCompleted by remember {
                mutableStateOf(prefs.getBoolean("onboarding_completed", false))
            }
            var themeMode by remember {
                mutableStateOf(prefs.getString("theme_mode", "dark") ?: "dark")
            }
            AirbridgeTheme(themeMode = themeMode) {
                var showQrScanner by remember { mutableStateOf(false) }
                var showPairingSuccess by remember { mutableStateOf(false) }
                var pairedMacName by remember { mutableStateOf("") }

                if (showQrScanner) {
                    com.airbridge.pairing.QrScannerScreen(
                        onScanned = { payload ->
                            showQrScanner = false
                            pairedMacName = "Mac"
                            showPairingSuccess = true
                            viewModel.handlePairingPayload(payload)
                            prefs.edit().putBoolean("onboarding_completed", true).apply()
                        },
                        onDismiss = {
                            showQrScanner = false
                        }
                    )
                } else if (showPairingSuccess) {
                    PairingSuccessScreen(
                        deviceName = pairedMacName,
                        onContinue = {
                            showPairingSuccess = false
                            onboardingCompleted = true
                        }
                    )
                } else if (onboardingCompleted) {
                    data class NavItem(
                        val labelRes: Int,
                        val icon: ImageVector
                    )

                    // Dolny pasek: tylko miejsca główne. Ustawienia i O aplikacji
                    // przeniesione do górnego paska.
                    val navItems = listOf(
                        NavItem(R.string.nav_home, Icons.Rounded.Home),
                        NavItem(R.string.nav_screen_sharing, Icons.Rounded.ScreenShare)
                    )
                    // Tytuł w górnym pasku = nazwa bieżącej strony pagera (2 strony).
                    val pageTitles = listOf(
                        R.string.app_name,
                        R.string.nav_screen_sharing
                    )

                    val pagerState = rememberPagerState(pageCount = { 2 })
                    val coroutineScope = rememberCoroutineScope()
                    val pairedDeviceStore = remember { com.airbridge.security.PairedDeviceStore(this@MainActivity) }
                    val pairedDevicesRevision by com.airbridge.security.PairedDeviceStore.revision.collectAsState()
                    val hasPairedDevices = remember(pairedDevicesRevision) {
                        pairedDeviceStore.getAll().isNotEmpty()
                    }
                    var fabMenuExpanded by remember { mutableStateOf(false) }
                    var topMenuExpanded by remember { mutableStateOf(false) }
                    var showSettings by remember { mutableStateOf(false) }
                    var showAbout by remember { mutableStateOf(false) }
                    var pendingFileUri by remember { mutableStateOf<Uri?>(null) }
                    var pendingIsPhoto by remember { mutableStateOf(false) }
                    val context = LocalContext.current
                    val haptic = LocalHapticFeedback.current

                    // Pickers — store URI for confirmation instead of sending immediately
                    val filePickerLauncher = rememberLauncherForActivityResult(
                        contract = ActivityResultContracts.OpenDocument()
                    ) { uri: Uri? ->
                        uri?.let {
                            pendingFileUri = it
                            pendingIsPhoto = false
                        }
                    }
                    val photoPickerLauncher = rememberLauncherForActivityResult(
                        contract = ActivityResultContracts.PickVisualMedia()
                    ) { uri: Uri? ->
                        uri?.let {
                            pendingFileUri = it
                            pendingIsPhoto = true
                        }
                    }

                    Scaffold(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                        topBar = {
                            TopAppBar(
                                title = {
                                    Text(stringResource(pageTitles[pagerState.targetPage.coerceIn(0, pageTitles.lastIndex)]))
                                },
                                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                                    scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                                ),
                                actions = {
                                    IconButton(onClick = { showSettings = true }) {
                                        Icon(Icons.Rounded.Settings, contentDescription = stringResource(R.string.nav_settings))
                                    }
                                    IconButton(onClick = { topMenuExpanded = true }) {
                                        Icon(Icons.Rounded.MoreVert, contentDescription = stringResource(R.string.nav_about))
                                    }
                                    DropdownMenu(
                                        expanded = topMenuExpanded,
                                        onDismissRequest = { topMenuExpanded = false }
                                    ) {
                                        DropdownMenuItem(
                                            text = { Text(stringResource(R.string.nav_about)) },
                                            leadingIcon = { Icon(Icons.Rounded.Info, contentDescription = null) },
                                            onClick = {
                                                topMenuExpanded = false
                                                showAbout = true
                                            }
                                        )
                                    }
                                }
                            )
                        },
                        bottomBar = {
                            // Material 3 Expressive compact dock. ShortNavigationBar
                            // gives the spec-correct short bar + tight active-indicator
                            // pill bounded to the item (the ripple no longer floods
                            // half the bar like a hand-rolled Row would).
                            ShortNavigationBar(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
                            ) {
                                val itemColors = ShortNavigationBarItemDefaults.colors(
                                    selectedIconColor = MaterialTheme.colorScheme.primary,
                                    unselectedIconColor = MaterialTheme.colorScheme.onSurface,
                                    selectedIndicatorColor = MaterialTheme.colorScheme.primaryContainer
                                )
                                navItems.forEachIndexed { index, item ->
                                    ShortNavigationBarItem(
                                        selected = pagerState.targetPage == index,
                                        onClick = {
                                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                            coroutineScope.launch {
                                                pagerState.animateScrollToPage(index)
                                            }
                                        },
                                        icon = {
                                            Icon(
                                                item.icon,
                                                contentDescription = stringResource(item.labelRes)
                                            )
                                        },
                                        label = null,
                                        colors = itemColors
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
                                            onCheckedChange = { fabMenuExpanded = it }
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
                                    FloatingActionButtonMenuItem(
                                        onClick = {
                                            fabMenuExpanded = false
                                            filePickerLauncher.launch(arrayOf("*/*"))
                                        },
                                        icon = { Icon(Icons.AutoMirrored.Rounded.InsertDriveFile, contentDescription = null) },
                                        text = { Text(stringResource(R.string.action_send_file)) }
                                    )
                                    FloatingActionButtonMenuItem(
                                        onClick = {
                                            fabMenuExpanded = false
                                            photoPickerLauncher.launch(
                                                androidx.activity.result.PickVisualMediaRequest(
                                                    ActivityResultContracts.PickVisualMedia.ImageAndVideo
                                                )
                                            )
                                        },
                                        icon = { Icon(Icons.Rounded.Photo, contentDescription = null) },
                                        text = { Text(stringResource(R.string.action_send_photo)) }
                                    )
                                    FloatingActionButtonMenuItem(
                                        onClick = {
                                            fabMenuExpanded = false
                                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                            val clip = clipboard.primaryClip
                                            val text = if (clip != null && clip.itemCount > 0)
                                                clip.getItemAt(0).coerceToText(context).toString() else ""
                                            if (text.isNotEmpty()) {
                                                viewModel.sendClipboard(text)
                                                Toast.makeText(context, context.getString(R.string.sent_to_mac), Toast.LENGTH_SHORT).show()
                                            } else {
                                                Toast.makeText(context, context.getString(R.string.clipboard_empty), Toast.LENGTH_SHORT).show()
                                            }
                                        },
                                        icon = { Icon(Icons.Rounded.ContentPaste, contentDescription = null) },
                                        text = { Text(stringResource(R.string.action_send_clipboard)) }
                                    )
                                }
                            }
                        },
                        floatingActionButtonPosition = FabPosition.End
                    ) { innerPadding ->
                        HorizontalPager(
                            state = pagerState,
                            modifier = Modifier.padding(innerPadding),
                            beyondViewportPageCount = 1,
                        ) { page ->
                            when (page) {
                                0 -> MainScreen(viewModel = viewModel, onScanQr = { showQrScanner = true })
                                1 -> ScreenShareScreen()
                            }
                        }
                    }

                    // Ustawienia / O aplikacji — pełne ekrany otwierane z paska
                    // (nie strony pagera, więc nie da się ich wyswipe'ować).
                    AnimatedVisibility(
                        visible = showSettings,
                        enter = slideInHorizontally(
                            animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
                            initialOffsetX = { it }
                        ),
                        exit = slideOutHorizontally(
                            animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
                            targetOffsetX = { it }
                        )
                    ) {
                        BackHandler { showSettings = false }
                        Scaffold(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                            topBar = {
                                TopAppBar(
                                    title = { Text(stringResource(R.string.nav_settings)) },
                                    navigationIcon = {
                                        IconButton(onClick = { showSettings = false }) {
                                            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                                        }
                                    },
                                    colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                                        scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                                    )
                                )
                            }
                        ) { pad ->
                            Box(modifier = Modifier.padding(pad)) {
                                SettingsScreen(
                                    prefs = prefs,
                                    onThemeChanged = { themeMode = it },
                                    onScanQr = {
                                        showSettings = false
                                        showQrScanner = true
                                    }
                                )
                            }
                        }
                    }
                    AnimatedVisibility(
                        visible = showAbout,
                        enter = slideInHorizontally(
                            animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec(),
                            initialOffsetX = { it }
                        ),
                        exit = slideOutHorizontally(
                            animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
                            targetOffsetX = { it }
                        )
                    ) {
                        BackHandler { showAbout = false }
                        Scaffold(
                            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                            topBar = {
                                TopAppBar(
                                    title = { Text(stringResource(R.string.nav_about)) },
                                    navigationIcon = {
                                        IconButton(onClick = { showAbout = false }) {
                                            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                                        }
                                    },
                                    colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                                        scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh
                                    )
                                )
                            }
                        ) { pad ->
                            Box(modifier = Modifier.padding(pad)) {
                                AboutScreen()
                            }
                        }
                    }

                    // File/photo confirmation sheet
                    if (pendingFileUri != null) {
                        ModalBottomSheet(
                            onDismissRequest = { pendingFileUri = null },
                            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                        ) {
                            SendConfirmationSheet(
                                uri = pendingFileUri!!,
                                isPhoto = pendingIsPhoto,
                                onConfirm = {
                                    viewModel.sendFile(pendingFileUri!!)
                                    Toast.makeText(context, context.getString(R.string.sent_to_mac), Toast.LENGTH_SHORT).show()
                                    pendingFileUri = null
                                },
                                onCancel = { pendingFileUri = null }
                            )
                        }
                    }
                } else {
                    OnboardingScreen(
                        onFinished = {
                            prefs.edit().putBoolean("onboarding_completed", true).apply()
                            onboardingCompleted = true
                        },
                        onScanQr = {
                            showQrScanner = true
                        },
                        onSkipPairing = {
                            prefs.edit().putBoolean("onboarding_completed", true).apply()
                            onboardingCompleted = true
                        }
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Returning to the app is the user's cue that they expect a connection.
        // If a background discovery had gone stale (network switched while we
        // were away), this recovers it at once; the service ignores it when
        // already connected.
        viewModel.rediscover()
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
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
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
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
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
