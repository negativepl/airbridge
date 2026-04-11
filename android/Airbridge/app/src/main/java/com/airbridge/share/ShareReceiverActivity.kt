package com.airbridge.share

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.TextSnippet
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.airbridge.R
import com.airbridge.security.PairedDevice
import com.airbridge.security.PairedDeviceStore
import com.airbridge.service.AirbridgeService
import com.airbridge.ui.AirbridgeTheme
import kotlinx.coroutines.flow.StateFlow
import androidx.compose.runtime.collectAsState

/**
 * Full-screen share target shown when the user shares a file/text from
 * another app via AirBridge. Parses the incoming intent, shows a list of
 * paired Macs (with the currently-connected one marked as Connected and
 * auto-selected), and on Send forwards the data to
 * `AirbridgeService.ACTION_SEND_FILE`.
 *
 * Lives in its own task (`taskAffinity=""` + `excludeFromRecents="true"`)
 * so dismissing via Close / back / Cancel returns the user to the source
 * app instead of dragging the main AirBridge UI to front.
 *
 * Note: the service today only holds one active connection at a time, so
 * the device list is effectively [connected Mac] + [other paired Macs marked
 * offline and disabled]. The UI is already shaped for multi-device selection
 * so future multi-connection work plugs in without a redesign.
 */
/// File-scoped payload extracted from the incoming share intent. Lives at
/// file level (not nested) so the private composables below can reference it.
private data class ParsedShare(
    val fileUris: List<Uri>,
    val text: String?
)

class ShareReceiverActivity : ComponentActivity() {

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Parse the incoming share intent ONCE in onCreate so rotation / recreation
        // doesn't re-parse (and can't — the original intent is held by the activity).
        val parsed = parseShareIntent(intent)
        if (parsed == null) {
            finish()
            return
        }

        // Ensure the service is alive so device discovery / connection state is
        // current by the time the user taps Send. Safe to call repeatedly — the
        // service short-circuits if already running.
        startService(Intent(this, AirbridgeService::class.java))

        val pairedDevices = PairedDeviceStore(this).getAll()

        val prefs = getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE)
        val themeMode = prefs.getString("theme_mode", "system") ?: "system"

        setContent {
            AirbridgeTheme(themeMode = themeMode) {
                val isConnected by AirbridgeService.isConnected.collectAsStateSafe(false)
                val connectedDeviceName by AirbridgeService.connectedDeviceName.collectAsStateSafe(null)

                // Auto-select the currently-connected device. Matching is by
                // device name — if the user has multiple Macs with the same
                // display name the first wins (rare). Fingerprint-based match
                // would be cleaner once the service tracks that.
                var selectedFingerprint by remember(connectedDeviceName) {
                    mutableStateOf(
                        pairedDevices.firstOrNull { isConnected && it.deviceName == connectedDeviceName }
                            ?.publicKeyFingerprint
                            ?: pairedDevices.firstOrNull()?.publicKeyFingerprint
                    )
                }
                val selectedDevice = pairedDevices.firstOrNull { it.publicKeyFingerprint == selectedFingerprint }
                val selectedIsOnline = selectedDevice != null &&
                    isConnected && selectedDevice.deviceName == connectedDeviceName

                Scaffold(
                    topBar = {
                        CenterAlignedTopAppBar(
                            title = {
                                Text(
                                    text = stringResource(R.string.share_sheet_title),
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                            },
                            navigationIcon = {
                                IconButton(onClick = { finish() }) {
                                    Icon(
                                        imageVector = Icons.Rounded.Close,
                                        contentDescription = stringResource(R.string.send_confirm_cancel)
                                    )
                                }
                            },
                            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                                containerColor = MaterialTheme.colorScheme.surface
                            )
                        )
                    },
                    bottomBar = {
                        ShareSheetBottomBar(
                            sendEnabled = selectedIsOnline,
                            onCancel = { finish() },
                            onSend = {
                                if (selectedIsOnline) {
                                    dispatchSend(parsed)
                                    Toast.makeText(
                                        this@ShareReceiverActivity,
                                        R.string.share_sending,
                                        Toast.LENGTH_SHORT
                                    ).show()
                                }
                                finish()
                            }
                        )
                    },
                    containerColor = MaterialTheme.colorScheme.surface
                ) { padding ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 24.dp, vertical = 8.dp)
                    ) {
                        SharePreview(parsed)

                        Spacer(Modifier.height(32.dp))

                        Text(
                            text = stringResource(R.string.share_sheet_devices),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        Spacer(Modifier.height(12.dp))

                        if (pairedDevices.isEmpty()) {
                            EmptyDevicesState()
                        } else {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                pairedDevices.forEach { device ->
                                    val online = isConnected && device.deviceName == connectedDeviceName
                                    val isSelected = device.publicKeyFingerprint == selectedFingerprint
                                    DeviceRow(
                                        device = device,
                                        isOnline = online,
                                        isSelected = isSelected,
                                        onClick = { selectedFingerprint = device.publicKeyFingerprint }
                                    )
                                }
                            }
                        }

                        Spacer(Modifier.height(24.dp))
                    }
                }
            }
        }
    }

    // --- Intent parsing ---

    private fun parseShareIntent(intent: Intent): ParsedShare? {
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val uri: Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                when {
                    uri != null -> ParsedShare(fileUris = listOf(uri), text = null)
                    !text.isNullOrEmpty() -> ParsedShare(fileUris = emptyList(), text = text)
                    else -> null
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris: ArrayList<Uri>? =
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                if (uris.isNullOrEmpty()) null
                else ParsedShare(fileUris = uris.toList(), text = null)
            }
            else -> null
        }
    }

    private fun dispatchSend(parsed: ParsedShare) {
        // Fire off one service intent per file URI (preserves existing
        // per-file send flow) and one for text if present. The service's
        // handleSendFile handles each individually.
        parsed.fileUris.forEach { uri ->
            startService(
                Intent(this, AirbridgeService::class.java).apply {
                    action = AirbridgeService.ACTION_SEND_FILE
                    data = uri
                }
            )
        }
        parsed.text?.let { text ->
            startService(
                Intent(this, AirbridgeService::class.java).apply {
                    action = AirbridgeService.ACTION_SEND_FILE
                    putExtra(Intent.EXTRA_TEXT, text)
                }
            )
        }
    }

    // Small helper to bridge a kotlinx StateFlow into Compose state while this
    // activity is alive. Material3's `collectAsState` extension is on Flow, so
    // we use it directly — this alias just makes intent clearer at call site.
    @Composable
    private fun <T> StateFlow<T>.collectAsStateSafe(initial: T) =
        collectAsState(initial = this.value ?: initial)
}

// MARK: - Composables (private, file-scoped)

@Composable
private fun ShareSheetBottomBar(
    sendEnabled: Boolean,
    onCancel: () -> Unit,
    onSend: () -> Unit
) {
    // Elevated surface so the bottom bar visually separates from the scrolling
    // content above. navigationBarsPadding keeps the buttons clear of the
    // system gesture bar on phones without hardware buttons.
    Surface(
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 3.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            TextButton(
                onClick = onCancel,
                modifier = Modifier
                    .weight(1f)
                    .height(52.dp)
            ) {
                Text(
                    text = stringResource(R.string.send_confirm_cancel),
                    style = MaterialTheme.typography.labelLarge
                )
            }
            Button(
                onClick = onSend,
                enabled = sendEnabled,
                modifier = Modifier
                    .weight(1f)
                    .height(52.dp),
                shape = RoundedCornerShape(50)
            ) {
                Icon(
                    imageVector = Icons.Rounded.FileUpload,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.share_sheet_send),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }
}

@Composable
private fun EmptyDevicesState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Rounded.Computer,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(40.dp)
        )
        Spacer(Modifier.height(12.dp))
        Text(
            text = stringResource(R.string.share_sheet_no_devices),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = stringResource(R.string.share_sheet_no_devices_desc),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SharePreview(parsed: ParsedShare) {
    val context = LocalContext.current

    // Text share: show a text snippet icon + character count
    if (parsed.text != null) {
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
                    imageVector = Icons.AutoMirrored.Rounded.TextSnippet,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(24.dp)
                )
            }
            Spacer(Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = parsed.text.take(80),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = stringResource(R.string.share_sheet_text_preview, parsed.text.length),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        return
    }

    // Multi-file share: collapsed tile showing count
    if (parsed.fileUris.size > 1) {
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
            Spacer(Modifier.width(16.dp))
            Text(
                text = stringResource(R.string.share_sheet_multiple_files, parsed.fileUris.size),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        return
    }

    // Single file: try to resolve filename + size + image preview
    val uri = parsed.fileUris.firstOrNull() ?: return

    val (fileName, fileSize, isImage) = remember(uri) {
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
        val mime = context.contentResolver.getType(uri) ?: ""
        Triple(name, size, mime.startsWith("image/"))
    }

    val sizeText = when {
        fileSize <= 0 -> ""
        fileSize < 1024 -> "$fileSize B"
        fileSize < 1024 * 1024 -> "${fileSize / 1024} KB"
        else -> String.format("%.1f MB", fileSize / (1024.0 * 1024.0))
    }

    if (isImage) {
        Column(modifier = Modifier.fillMaxWidth()) {
            AsyncImage(
                model = uri,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 10f)
                    .clip(RoundedCornerShape(20.dp))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            )
            Spacer(Modifier.height(12.dp))
            Text(
                text = fileName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            if (sizeText.isNotEmpty()) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = sizeText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
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
            Spacer(Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = fileName,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (sizeText.isNotEmpty()) {
                    Text(
                        text = sizeText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun DeviceRow(
    device: PairedDevice,
    isOnline: Boolean,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val bg = when {
        isSelected && isOnline -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surfaceContainerHigh
    }
    val contentColor = when {
        isSelected && isOnline -> MaterialTheme.colorScheme.onPrimaryContainer
        isOnline -> MaterialTheme.colorScheme.onSurface
        else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
    }
    val statusColor = when {
        isOnline -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(bg)
            .clickable(enabled = isOnline, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(
                    if (isOnline) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Rounded.Computer,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(22.dp)
            )
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = device.deviceName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = contentColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = stringResource(
                    if (isOnline) R.string.share_sheet_connected
                    else R.string.share_sheet_offline
                ),
                style = MaterialTheme.typography.bodySmall,
                color = statusColor
            )
        }
        if (isSelected && isOnline) {
            Icon(
                imageVector = Icons.Rounded.Check,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(22.dp)
            )
        }
    }
}
