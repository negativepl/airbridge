package com.airbridge.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.content.SharedPreferences
import com.airbridge.service.AirbridgeService
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.IconButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.BrightnessAuto
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.SystemUpdate
import android.widget.Toast
import com.airbridge.diagnostics.DiagnosticReportExporter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.graphics.Color
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.airbridge.R
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import com.airbridge.service.HeadphoneManager

@Composable
fun SettingsScreen(
    prefs: SharedPreferences,
    onThemeChanged: (String) -> Unit,
    onScanQr: () -> Unit = {},
    onBack: () -> Unit = {}
) {
    BackHandler { onBack() }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        topBar = {
            key(MaterialTheme.colorScheme.surfaceContainer) {
                TopAppBar(
                    title = { Text(stringResource(R.string.nav_settings)) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(
                                Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = stringResource(R.string.nav_back)
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainer,
                        scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainer
                    )
                )
            }
        }
    ) { pad ->
        SettingsContent(prefs, onThemeChanged, onScanQr, Modifier.padding(pad))
    }
}

@Composable
private fun SettingsContent(
    prefs: SharedPreferences,
    onThemeChanged: (String) -> Unit,
    onScanQr: () -> Unit,
    modifier: Modifier = Modifier
) {
    var themeMode by remember { mutableStateOf(prefs.getString("theme_mode", "system") ?: "system") }
    var autoConnect by remember { mutableStateOf(prefs.getBoolean("auto_connect", true)) }
    var vibrateOnSync by remember { mutableStateOf(prefs.getBoolean("vibrate_on_sync", false)) }
    var headphoneHandoff by remember {
        mutableStateOf(prefs.getBoolean("headphone_handoff_enabled", false))
    }
    var headphoneName by remember {
        mutableStateOf(prefs.getString("headphone_name", null))
    }
    var headphoneAutoSwitch by remember {
        mutableStateOf(prefs.getBoolean("headphone_auto_switch", false))
    }
    var showHeadphonePicker by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val btPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) showHeadphonePicker = true }

    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 8.dp)
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // Paired Devices section
        SectionHeader(text = stringResource(R.string.pairing_paired_devices))

        val context = LocalContext.current
        val pairedDeviceStore = remember { com.airbridge.security.PairedDeviceStore(context) }
        val pairedDevicesRevision by com.airbridge.security.PairedDeviceStore.revision.collectAsState()
        val pairedDevices = remember(pairedDevicesRevision) { pairedDeviceStore.getAll() }

        // Live Mac data, available only while the paired Mac is connected, so the
        // card can mirror the home-screen hero (wallpaper + hardware name).
        val macInfo by com.airbridge.service.AirbridgeService.macInfo.collectAsState()
        val macWallpaper by com.airbridge.service.AirbridgeService.macWallpaper.collectAsState()
        val connectedDeviceName by com.airbridge.service.AirbridgeService.connectedDeviceName.collectAsState()

        if (pairedDevices.isEmpty()) {
            Text(
                text = stringResource(R.string.pairing_no_devices),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp)
            )
        } else {
            pairedDevices.forEach { device ->
                val isLive = connectedDeviceName == device.deviceName
                val liveWallpaper = if (isLive) macWallpaper else null
                // Prefer the live wallpaper; fall back to the last cached one so the
                // card still shows the Mac's wallpaper while it's offline.
                val wallpaper = remember(liveWallpaper, device.deviceName, pairedDevicesRevision) {
                    val live = liveWallpaper?.let {
                        runCatching {
                            val bytes = Base64.decode(it, Base64.NO_WRAP)
                            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        }.getOrNull()
                    }
                    (live ?: com.airbridge.device.WallpaperCache.load(context, device.deviceName))
                        ?.asImageBitmap()
                }
                PairedDeviceCard(
                    deviceName = device.deviceName,
                    subtitle = if (isLive && macInfo != null) {
                        "${macInfo!!.model} · ${macInfo!!.chip}"
                    } else {
                        stringResource(
                            R.string.pairing_paired_on,
                            java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM)
                                .format(java.util.Date(device.pairedAt))
                        )
                    },
                    wallpaper = wallpaper,
                    isConnected = isLive,
                    onRemove = {
                        com.airbridge.device.WallpaperCache.delete(context, device.deviceName)
                        pairedDeviceStore.remove(device.publicKeyFingerprint)
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
        }

        // Add new Mac button
        Button(
            onClick = { onScanQr() },
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
        ) {
            Text(stringResource(R.string.pairing_add_mac))
        }

        // Appearance section
            SectionHeader(text = stringResource(R.string.settings_appearance))
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    // Jasny | Systemowy | Ciemny — systemowy w środku jako
                    // punkt neutralny między dwoma jawnymi motywami.
                    val themeOptions = listOf(
                        Triple("light", stringResource(R.string.settings_theme_light), Icons.Rounded.LightMode),
                        Triple("system", stringResource(R.string.settings_theme_system), Icons.Rounded.BrightnessAuto),
                        Triple("dark", stringResource(R.string.settings_theme_dark), Icons.Rounded.DarkMode)
                    )

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectableGroup(),
                        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween)
                    ) {
                        themeOptions.forEachIndexed { index, option ->
                            val (value, label, themeIcon) = option
                            ToggleButton(
                                checked = themeMode == value,
                                onCheckedChange = {
                                    themeMode = value
                                    prefs.edit { putString("theme_mode", value) }
                                    onThemeChanged(value)
                                },
                                modifier = Modifier
                                    .weight(1f)
                                    .semantics { role = Role.RadioButton },
                                shapes = when (index) {
                                    0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
                                    themeOptions.lastIndex -> ButtonGroupDefaults.connectedTrailingButtonShapes()
                                    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
                                },
                                icon = { Icon(themeIcon, contentDescription = null) }
                            ) {
                                Text(label, maxLines = 1)
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Download folder section
            SectionHeader(text = stringResource(R.string.settings_download_folder))
            Spacer(modifier = Modifier.height(8.dp))
            run {
                val defaultFolder = android.os.Environment.getExternalStoragePublicDirectory(
                    android.os.Environment.DIRECTORY_DOWNLOADS
                ).absolutePath + "/AirBridge"
                var downloadFolder by remember {
                    mutableStateOf(prefs.getString("download_folder", defaultFolder) ?: defaultFolder)
                }
                val folderPicker = rememberLauncherForActivityResult(
                    ActivityResultContracts.OpenDocumentTree()
                ) { uri ->
                    if (uri != null) {
                        val path = uri.path?.replace("/tree/primary:", "/storage/emulated/0/") ?: return@rememberLauncherForActivityResult
                        downloadFolder = path
                        prefs.edit { putString("download_folder", path) }
                    }
                }
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { folderPicker.launch(null) },
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                    )
                ) {
                    ListItem(
                        content = {
                            Text(
                                text = downloadFolder,
                                maxLines = 1,
                                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                            )
                        },
                        supportingContent = {
                            Text(stringResource(R.string.settings_download_folder_desc))
                        },
                        trailingContent = {
                            Icon(
                                Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Notifications section
            SectionHeader(text = stringResource(R.string.settings_notifications))
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                            putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, com.airbridge.service.AirbridgeService.CHANNEL_ID)
                        }
                        context.startActivity(intent)
                    },
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    content = {
                        Text(stringResource(R.string.settings_hide_notification))
                    },
                    supportingContent = {
                        Text(stringResource(R.string.settings_hide_notification_desc))
                    },
                    trailingContent = {
                        Icon(
                            Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    content = { Text(stringResource(R.string.settings_vibrate)) },
                    supportingContent = { Text(stringResource(R.string.settings_vibrate_desc)) },
                    trailingContent = {
                        Switch(checked = vibrateOnSync, onCheckedChange = null)
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.toggleable(
                        value = vibrateOnSync,
                        role = Role.Switch,
                        onValueChange = {
                            vibrateOnSync = it
                            prefs.edit { putBoolean("vibrate_on_sync", it) }
                        }
                    )
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Connection section
            SectionHeader(text = stringResource(R.string.settings_connection))
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    content = { Text(stringResource(R.string.settings_auto_connect)) },
                    supportingContent = { Text(stringResource(R.string.settings_auto_connect_desc)) },
                    trailingContent = {
                        Switch(checked = autoConnect, onCheckedChange = null)
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.toggleable(
                        value = autoConnect,
                        role = Role.Switch,
                        onValueChange = {
                            autoConnect = it
                            prefs.edit { putBoolean("auto_connect", it) }
                        }
                    )
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            SectionHeader(text = stringResource(R.string.settings_headphones))
            Spacer(modifier = Modifier.height(8.dp))
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    content = { Text(stringResource(R.string.settings_headphone_handoff)) },
                    supportingContent = { Text(stringResource(R.string.settings_headphone_handoff_desc)) },
                    trailingContent = {
                        Switch(checked = headphoneHandoff, onCheckedChange = null)
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.toggleable(
                        value = headphoneHandoff,
                        role = Role.Switch,
                        onValueChange = {
                            headphoneHandoff = it
                            prefs.edit { putBoolean("headphone_handoff_enabled", it) }
                            ContextCompat.startForegroundService(
                                context,
                                Intent(context, AirbridgeService::class.java)
                                    .setAction(AirbridgeService.ACTION_HEADPHONE_REFRESH)
                            )
                        }
                    )
                )
                if (headphoneHandoff) {
                    ListItem(
                        content = { Text(stringResource(R.string.settings_headphone_device)) },
                        supportingContent = {
                            Text(headphoneName ?: stringResource(R.string.settings_headphone_device_none))
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.clickable {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                                ContextCompat.checkSelfPermission(
                                    context, Manifest.permission.BLUETOOTH_CONNECT
                                ) != PackageManager.PERMISSION_GRANTED
                            ) {
                                btPermissionLauncher.launch(Manifest.permission.BLUETOOTH_CONNECT)
                            } else {
                                showHeadphonePicker = true
                            }
                        }
                    )
                    ListItem(
                        content = { Text(stringResource(R.string.settings_headphone_auto)) },
                        supportingContent = { Text(stringResource(R.string.settings_headphone_auto_desc)) },
                        trailingContent = {
                            Switch(checked = headphoneAutoSwitch, onCheckedChange = null)
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.toggleable(
                            value = headphoneAutoSwitch,
                            role = Role.Switch,
                            onValueChange = {
                                headphoneAutoSwitch = it
                                prefs.edit { putBoolean("headphone_auto_switch", it) }
                                ContextCompat.startForegroundService(
                                    context,
                                    Intent(context, AirbridgeService::class.java)
                                        .setAction(AirbridgeService.ACTION_HEADPHONE_REFRESH)
                                )
                            }
                        )
                    )
                }
            }

            if (showHeadphonePicker) {
                val devices = remember { HeadphoneManager(context).bondedAudioDevices() }
                AlertDialog(
                    onDismissRequest = { showHeadphonePicker = false },
                    title = { Text(stringResource(R.string.settings_headphone_device)) },
                    text = {
                        if (devices.isEmpty()) {
                            Text(stringResource(R.string.settings_headphone_permission))
                        } else {
                            Column {
                                devices.forEach { device ->
                                    ListItem(
                                        content = { Text(device.name) },
                                        supportingContent = { Text(device.address) },
                                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                        modifier = Modifier.clickable {
                                            prefs.edit {
                                                putString("headphone_address", device.address)
                                                putString("headphone_name", device.name)
                                            }
                                            headphoneName = device.name
                                            showHeadphonePicker = false
                                            ContextCompat.startForegroundService(
                                                context,
                                                Intent(context, AirbridgeService::class.java)
                                                    .setAction(AirbridgeService.ACTION_HEADPHONE_REFRESH)
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    },
                    confirmButton = {
                        TextButton(onClick = { showHeadphonePicker = false }) {
                            Text(stringResource(android.R.string.cancel))
                        }
                    }
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Updates section — manual check only, never on a schedule.
            SectionHeader(text = stringResource(R.string.update_section_title))
            Spacer(modifier = Modifier.height(8.dp))
            var checkUpdateTrigger by remember { mutableStateOf(false) }
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { checkUpdateTrigger = true },
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    leadingContent = {
                        Icon(
                            Icons.Rounded.SystemUpdate,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                    },
                    content = { Text(stringResource(R.string.update_check)) },
                    trailingContent = {
                        Icon(
                            Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                )
            }
            com.airbridge.update.UpdateFlowHost(
                trigger = checkUpdateTrigger,
                onDone = { checkUpdateTrigger = false }
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Diagnostics section — builds the report off the main thread and
            // hands the file to the system share sheet; nothing is uploaded.
            SectionHeader(text = stringResource(R.string.settings_diagnostics))
            Spacer(modifier = Modifier.height(8.dp))
            val exportScope = rememberCoroutineScope()
            val exportFailedMessage = stringResource(R.string.settings_export_diagnostics_failed)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        exportScope.launch {
                            val intent = withContext(Dispatchers.IO) {
                                runCatching {
                                    val file = DiagnosticReportExporter.export(context)
                                    DiagnosticReportExporter.shareIntent(context, file)
                                }.getOrNull()
                            }
                            if (intent != null) {
                                context.startActivity(intent)
                            } else {
                                Toast.makeText(context, exportFailedMessage, Toast.LENGTH_SHORT).show()
                            }
                        }
                    },
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLowest
                )
            ) {
                ListItem(
                    leadingContent = {
                        Icon(
                            Icons.Rounded.Description,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                    },
                    content = { Text(stringResource(R.string.settings_export_diagnostics)) },
                    supportingContent = { Text(stringResource(R.string.settings_export_diagnostics_desc)) },
                    trailingContent = {
                        Icon(
                            Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                )
            }

        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
private fun PairedDeviceCard(
    deviceName: String,
    subtitle: String,
    wallpaper: androidx.compose.ui.graphics.ImageBitmap?,
    isConnected: Boolean,
    onRemove: () -> Unit
) {
    var showConfirm by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(160.dp)) {
            if (wallpaper != null) {
                Image(
                    bitmap = wallpaper,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().height(160.dp)
                )
            } else {
                Box(modifier = Modifier.fillMaxWidth().height(160.dp).background(MaterialTheme.colorScheme.primaryContainer))
            }
            Box(
                modifier = Modifier.fillMaxWidth().height(160.dp).background(
                    Brush.verticalGradient(0.4f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f))
                )
            )
            // Connection status — top-left pill, mirroring the home hero card.
            if (isConnected) {
                Row(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(12.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.Black.copy(alpha = 0.35f))
                        .padding(horizontal = 10.dp, vertical = 5.dp)
                ) {
                    Text(
                        stringResource(R.string.pairing_connected),
                        style = MaterialTheme.typography.labelLarge,
                        color = Color.White
                    )
                }
            }
            // Remove — top-right, woven into the image instead of a separate bar.
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.35f))
                    .clickable { showConfirm = true }
                    .padding(8.dp)
            ) {
                Icon(
                    Icons.Rounded.DeleteOutline,
                    contentDescription = stringResource(R.string.pairing_remove),
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }
            Column(modifier = Modifier.align(Alignment.BottomStart).padding(16.dp)) {
                Text(deviceName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Color.White)
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.85f)
                )
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text(stringResource(R.string.pairing_remove)) },
            text = { Text(stringResource(R.string.pairing_remove_confirm, deviceName)) },
            confirmButton = {
                TextButton(onClick = {
                    showConfirm = false
                    onRemove()
                }) {
                    Text(
                        text = stringResource(R.string.pairing_remove),
                        color = MaterialTheme.colorScheme.error
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) {
                    Text(stringResource(R.string.send_confirm_cancel))
                }
            }
        )
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 4.dp, top = 20.dp, bottom = 8.dp)
    )
}
