package com.airbridge.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.ui.draw.alpha
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
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
                mutableStateOf(prefs.getString("theme_mode", "system") ?: "system")
            }
            var showSplash by rememberSaveable { mutableStateOf(savedInstanceState == null) }

            Box {
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

                    val navItems = listOf(
                        NavItem(R.string.nav_home, Icons.Rounded.Home),
                        NavItem(R.string.nav_history, Icons.Rounded.History),
                        NavItem(R.string.nav_settings, Icons.Rounded.Settings),
                        NavItem(R.string.nav_about, Icons.Rounded.Info)
                    )

                    val pagerState = rememberPagerState(pageCount = { 4 })
                    val coroutineScope = rememberCoroutineScope()
                    val hasPairedDevices = remember {
                        com.airbridge.security.PairedDeviceStore(this@MainActivity).getAll().isNotEmpty()
                    }
                    var showSendSheet by remember { mutableStateOf(false) }
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
                        bottomBar = {
                            Box {
                                NavigationBar {
                                    // First 2 tabs (Home, History)
                                    val navBarColors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = MaterialTheme.colorScheme.primary,
                                        selectedTextColor = MaterialTheme.colorScheme.primary,
                                        unselectedIconColor = MaterialTheme.colorScheme.onSurface,
                                        unselectedTextColor = MaterialTheme.colorScheme.onSurface,
                                        indicatorColor = MaterialTheme.colorScheme.primaryContainer
                                    )
                                    navItems.take(2).forEachIndexed { index, item ->
                                        NavigationBarItem(
                                            selected = pagerState.targetPage == index,
                                            onClick = {
                                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                coroutineScope.launch {
                                                    pagerState.animateScrollToPage(index)
                                                }
                                            },
                                            icon = { Icon(item.icon, contentDescription = stringResource(item.labelRes)) },
                                            label = { Text(stringResource(item.labelRes), maxLines = 1) },
                                            colors = navBarColors
                                        )
                                    }

                                    // Empty space for FAB
                                    NavigationBarItem(
                                        selected = false,
                                        onClick = { showSendSheet = true },
                                        icon = { Spacer(Modifier.size(24.dp)) },
                                        label = { },
                                        enabled = false
                                    )

                                    // Last 2 tabs (Settings, About)
                                    navItems.drop(2).forEachIndexed { index, item ->
                                        NavigationBarItem(
                                            selected = pagerState.targetPage == index + 2,
                                            onClick = {
                                                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                                coroutineScope.launch {
                                                    pagerState.animateScrollToPage(index + 2)
                                                }
                                            },
                                            icon = { Icon(item.icon, contentDescription = stringResource(item.labelRes)) },
                                            label = { Text(stringResource(item.labelRes), maxLines = 1) },
                                            colors = navBarColors
                                        )
                                    }
                                }

                                // FAB centered over the bar
                                Column(
                                    modifier = Modifier
                                        .align(Alignment.TopCenter)
                                        .offset(y = (-14).dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    FloatingActionButton(
                                        onClick = { if (hasPairedDevices) showSendSheet = true },
                                        modifier = Modifier.size(64.dp),
                                        shape = CircleShape,
                                        containerColor = if (hasPairedDevices)
                                            MaterialTheme.colorScheme.primary
                                        else
                                            MaterialTheme.colorScheme.surfaceVariant,
                                        contentColor = if (hasPairedDevices)
                                            MaterialTheme.colorScheme.onPrimary
                                        else
                                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                        elevation = FloatingActionButtonDefaults.elevation(
                                            defaultElevation = 0.dp,
                                            pressedElevation = 0.dp,
                                            focusedElevation = 0.dp,
                                            hoveredElevation = 0.dp
                                        )
                                    ) {
                                        Icon(
                                            Icons.Rounded.FileUpload,
                                            contentDescription = stringResource(R.string.nav_send),
                                            modifier = Modifier.size(26.dp)
                                        )
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = stringResource(R.string.nav_send),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = if (hasPairedDevices)
                                            MaterialTheme.colorScheme.primary
                                        else
                                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                    )
                                }
                            }
                        }
                    ) { innerPadding ->
                        HorizontalPager(
                            state = pagerState,
                            modifier = Modifier.padding(innerPadding),
                            beyondBoundsPageCount = 3,
                            pageContent = { page ->
                                when (page) {
                                    0 -> MainScreen(viewModel = viewModel, onScanQr = { showQrScanner = true })
                                    1 -> HistoryScreen(viewModel = viewModel)
                                    2 -> SettingsScreen(
                                        prefs = prefs,
                                        onThemeChanged = { themeMode = it },
                                        onScanQr = { showQrScanner = true }
                                    )
                                    3 -> AboutScreen()
                                }
                            }
                        )
                    }

                    // Send bottom sheet
                    if (showSendSheet) {
                        ModalBottomSheet(
                            onDismissRequest = { showSendSheet = false },
                            sheetState = rememberModalBottomSheetState()
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 8.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.send_to_mac),
                                    style = MaterialTheme.typography.titleLarge,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                Spacer(modifier = Modifier.height(20.dp))

                                // Send file
                                SendOption(
                                    icon = Icons.AutoMirrored.Rounded.InsertDriveFile,
                                    label = stringResource(R.string.action_send_file),
                                    onClick = {
                                        showSendSheet = false
                                        filePickerLauncher.launch(arrayOf("*/*"))
                                    }
                                )

                                // Send photo
                                SendOption(
                                    icon = Icons.Rounded.Photo,
                                    label = stringResource(R.string.action_send_photo),
                                    onClick = {
                                        showSendSheet = false
                                        photoPickerLauncher.launch(
                                            ActivityResultContracts.PickVisualMedia
                                                .ImageAndVideo.let {
                                                    androidx.activity.result.PickVisualMediaRequest(it)
                                                }
                                        )
                                    }
                                )

                                // Send clipboard
                                SendOption(
                                    icon = Icons.Rounded.ContentPaste,
                                    label = stringResource(R.string.action_send_clipboard),
                                    onClick = {
                                        showSendSheet = false
                                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                        val clip = clipboard.primaryClip
                                        if (clip != null && clip.itemCount > 0) {
                                            val text = clip.getItemAt(0).coerceToText(context).toString()
                                            if (text.isNotEmpty()) {
                                                viewModel.sendClipboard(text)
                                                Toast.makeText(context, context.getString(R.string.sent_to_mac), Toast.LENGTH_SHORT).show()
                                            } else {
                                                Toast.makeText(context, context.getString(R.string.clipboard_empty), Toast.LENGTH_SHORT).show()
                                            }
                                        } else {
                                            Toast.makeText(context, context.getString(R.string.clipboard_empty), Toast.LENGTH_SHORT).show()
                                        }
                                    }
                                )

                                Spacer(modifier = Modifier.height(32.dp))
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
            // Splash overlay on top
            if (showSplash) {
                SplashScreen(onFinished = { showSplash = false })
            }
            }
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
            else -> String.format("%.1f MB", fileSize / (1024.0 * 1024.0))
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
                    .clip(RoundedCornerShape(16.dp)),
                contentScale = ContentScale.Crop
            )
            Spacer(modifier = Modifier.height(16.dp))
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
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
                .height(48.dp),
            shape = RoundedCornerShape(50)
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
                .height(48.dp),
            shape = RoundedCornerShape(50)
        ) {
            Text(stringResource(R.string.send_confirm_cancel))
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun SendOption(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 16.dp, horizontal = 16.dp),
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
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}
