package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.graphics.StrokeCap
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.DesktopMac
import androidx.compose.material.icons.rounded.LaptopMac
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Sensors
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.ActivityItem
import com.airbridge.service.AirbridgeService
import kotlinx.coroutines.delay

private val CardShape = RoundedCornerShape(24.dp)

@Composable
fun MainScreen(viewModel: MainViewModel, onScanQr: () -> Unit = {}) {
    val isConnected by viewModel.isConnected.collectAsState()
    val connectedDeviceName by viewModel.connectedDeviceName.collectAsState()
    val recentActivity by viewModel.recentActivity.collectAsState()
    val transferProgress by viewModel.transferProgress.collectAsState()
    val transferFileName by viewModel.transferFileName.collectAsState()
    val transferSpeedBps by viewModel.transferSpeedBps.collectAsState()
    val transferEtaSeconds by viewModel.transferEtaSeconds.collectAsState()
    val transferSpeedHistory by viewModel.transferSpeedHistory.collectAsState()

    val context = LocalContext.current
    val pairedDeviceStore = remember { com.airbridge.security.PairedDeviceStore(context) }
    val hasPairedDevices = remember { pairedDeviceStore.getAll().isNotEmpty() }

    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }

    if (!hasPairedDevices) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.pairing_no_devices),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = { onScanQr() },
                shape = RoundedCornerShape(50)
            ) {
                Text(stringResource(R.string.pairing_add_mac))
            }
        }
    } else {

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = stringResource(R.string.app_name),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(20.dp))

        // ── Device Card ──
        DeviceCard(
            isConnected = isConnected,
            deviceName = connectedDeviceName,
            onDisconnect = { viewModel.disconnect() },
            onReconnect = { viewModel.reconnect() }
        )

        // ── Transfer progress ──
        var transferExpanded by remember { mutableStateOf(false) }

        androidx.compose.animation.AnimatedVisibility(
            visible = transferProgress != null,
            enter = androidx.compose.animation.expandVertically() + androidx.compose.animation.fadeIn(),
            exit = androidx.compose.animation.shrinkVertically() + androidx.compose.animation.fadeOut()
        ) {
            Column {
            Spacer(modifier = Modifier.height(16.dp))

            Card(
                onClick = { transferExpanded = !transferExpanded },
                modifier = Modifier.fillMaxWidth(),
                shape = CardShape,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(
                    modifier = Modifier
                        .padding(16.dp)
                        .animateContentSize(
                            animationSpec = spring(
                                dampingRatio = 0.8f,
                                stiffness = 300f
                            )
                        )
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.transfer_sending),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                            if (transferFileName != null) {
                                Text(
                                    text = transferFileName!!,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                        Text(
                            text = if (transferProgress != null) stringResource(R.string.transfer_progress, (transferProgress!! * 100).toInt()) else "",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    LinearProgressIndicator(
                        progress = { transferProgress ?: 0f },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .clip(RoundedCornerShape(3.dp)),
                        color = MaterialTheme.colorScheme.primary,
                        trackColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.15f)
                    )

                    // Expanded section — speed chart + details
                    if (transferExpanded) {
                        Spacer(modifier = Modifier.height(12.dp))

                        // Speed chart
                        if (transferSpeedHistory.size > 2) {
                            SpeedChart(
                                data = transferSpeedHistory,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(120.dp)
                                    .clip(RoundedCornerShape(12.dp))
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                        }

                        // Speed + ETA
                        val speedText = when {
                            transferSpeedBps > 1024 * 1024 -> String.format("%.1f MB/s", transferSpeedBps / (1024.0 * 1024.0))
                            transferSpeedBps > 1024 -> String.format("%.0f KB/s", transferSpeedBps / 1024.0)
                            else -> ""
                        }
                        val etaText = when {
                            transferEtaSeconds > 60 -> "${transferEtaSeconds / 60} min ${transferEtaSeconds % 60} s"
                            transferEtaSeconds > 0 -> "${transferEtaSeconds} s"
                            else -> ""
                        }
                        if (speedText.isNotEmpty() || etaText.isNotEmpty()) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = speedText,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer
                                )
                                Text(
                                    text = etaText,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                                )
                            }
                        }

                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = stringResource(R.string.transfer_tap_collapse),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.5f),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier.fillMaxWidth()
                        )
                    } else {
                        // Collapsed — small speed text
                        val speedText = when {
                            transferSpeedBps > 1024 * 1024 -> String.format("%.1f MB/s", transferSpeedBps / (1024.0 * 1024.0))
                            transferSpeedBps > 1024 -> String.format("%.0f KB/s", transferSpeedBps / 1024.0)
                            else -> ""
                        }
                        if (speedText.isNotEmpty()) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = speedText,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
                            )
                        }
                    }
                }
            }
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        // ── Recent Transfers (last 3) ──
        Text(
            text = stringResource(R.string.recent_activity),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(bottom = 10.dp)
        )

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = CardShape,
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        ) {
            val lastThree = recentActivity.take(3)
            if (lastThree.isEmpty()) {
                Text(
                    text = stringResource(R.string.no_activity),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp)
                )
            } else {
                Column(modifier = Modifier.padding(16.dp)) {
                    lastThree.forEachIndexed { index, item ->
                        androidx.compose.animation.AnimatedVisibility(
                            visible = true,
                            enter = androidx.compose.animation.slideInVertically(
                                initialOffsetY = { -it },
                                animationSpec = androidx.compose.animation.core.tween(300, delayMillis = index * 50)
                            ) + androidx.compose.animation.fadeIn(
                                animationSpec = androidx.compose.animation.core.tween(300, delayMillis = index * 50)
                            )
                        ) {
                            RecentTransferRow(item = item, now = now)
                        }
                        if (index < lastThree.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(vertical = 10.dp),
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f)
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
    } // end else (hasPairedDevices)
}

// ── Device Card ──

@Composable
private fun DeviceCard(
    isConnected: Boolean,
    deviceName: String?,
    onDisconnect: () -> Unit,
    onReconnect: () -> Unit
) {
    val connectedHost by AirbridgeService.connectedHost.collectAsState()

    // Track previous state to detect connecting transition
    var wasConnected by remember { mutableStateOf(isConnected) }
    var showTransition by remember { mutableStateOf(false) }
    var transitionToConnected by remember { mutableStateOf(true) }

    LaunchedEffect(isConnected) {
        if (isConnected != wasConnected) {
            transitionToConnected = isConnected
            showTransition = true
            delay(1200)
            showTransition = false
        }
        wasConnected = isConnected
    }

    // 0 = disconnected, 1 = transition (connecting/disconnecting), 2 = connected
    val state = when {
        showTransition -> 1
        isConnected && deviceName != null -> 2
        else -> 0
    }

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = CardShape,
        tonalElevation = 2.dp,
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        androidx.compose.animation.AnimatedContent(
            targetState = state,
            transitionSpec = {
                (androidx.compose.animation.fadeIn(
                    animationSpec = androidx.compose.animation.core.tween(300)
                ) + androidx.compose.animation.scaleIn(
                    initialScale = 0.95f,
                    animationSpec = androidx.compose.animation.core.tween(300)
                )) togetherWith (androidx.compose.animation.fadeOut(
                    animationSpec = androidx.compose.animation.core.tween(200)
                ))
            },
            label = "deviceCardState"
        ) { currentState ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                when (currentState) {
                    2 -> {
                        // Connected
                        val name = deviceName ?: "Mac"
                        val macIcon = when {
                            name.contains("MacBook", ignoreCase = true) -> Icons.Rounded.LaptopMac
                            name.contains("iMac", ignoreCase = true) -> Icons.Rounded.DesktopMac
                            else -> Icons.Rounded.Computer
                        }

                        Box(
                            modifier = Modifier
                                .size(80.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(MaterialTheme.colorScheme.primaryContainer),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = macIcon,
                                contentDescription = null,
                                modifier = Modifier.size(40.dp),
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        Text(
                            text = name,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = stringResource(R.string.connected),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary
                        )

                        if (connectedHost != null) {
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = connectedHost!!,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }

                        Spacer(modifier = Modifier.height(24.dp))

                        androidx.compose.material3.FilledTonalButton(
                            onClick = onDisconnect,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp),
                            shape = RoundedCornerShape(50)
                        ) {
                            Icon(
                                Icons.Rounded.LinkOff,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                stringResource(R.string.disconnect),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                    }
                    1 -> {
                        // Transition
                        Box(
                            modifier = Modifier
                                .size(80.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(MaterialTheme.colorScheme.primaryContainer),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(36.dp),
                                color = MaterialTheme.colorScheme.primary,
                                strokeWidth = 3.dp
                            )
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        Text(
                            text = if (transitionToConnected)
                                stringResource(R.string.connecting)
                            else
                                stringResource(R.string.disconnecting),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = deviceName ?: "Mac",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    else -> {
                        // Disconnected
                        Box(
                            modifier = Modifier
                                .size(80.dp)
                                .clip(androidx.compose.foundation.shape.CircleShape)
                                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.WifiOff,
                                contentDescription = null,
                                modifier = Modifier.size(40.dp),
                                tint = MaterialTheme.colorScheme.outlineVariant
                            )
                        }

                        Spacer(modifier = Modifier.height(16.dp))

                        Text(
                            text = stringResource(R.string.not_connected),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = stringResource(R.string.searching),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(24.dp))

                        androidx.compose.material3.FilledTonalButton(
                            onClick = onReconnect,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp),
                            shape = RoundedCornerShape(50)
                        ) {
                            Icon(
                                Icons.Rounded.Refresh,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                stringResource(R.string.reconnect),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                    }
                }
            }
        }
    }
}

// ── Recent Transfer Row ──

// ── Recent Transfer Row ──

@Composable
private fun RecentTransferRow(item: ActivityItem, now: Long) {
    val icon = when {
        item.type.contains("clipboard") -> Icons.Rounded.ContentPaste
        item.type.contains("file") -> Icons.AutoMirrored.Rounded.InsertDriveFile
        else -> Icons.Rounded.Sensors
    }

    val isSent = item.type.contains("sent")
    val iconTint = if (isSent)
        MaterialTheme.colorScheme.primary
    else
        MaterialTheme.colorScheme.tertiary

    val deviceName = AirbridgeService.connectedDeviceName.value ?: "Mac"
    val label = when (item.type) {
        "clipboard_sent" -> stringResource(R.string.clipboard_sent_to_mac)
        "clipboard_received" -> stringResource(R.string.clipboard_received_from, deviceName)
        "file_sent" -> stringResource(R.string.file_sent_to_mac)
        "file_received" -> stringResource(R.string.file_received_from, deviceName)
        "ping" -> if (item.description == "Ping") stringResource(R.string.ping_sent) else stringResource(R.string.pong_received)
        else -> item.description
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = iconTint
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = formatTimeAgo(item.timestamp, now),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.outline
        )
    }
}

// ── Speed Chart ──

@Composable
private fun SpeedChart(data: List<Float>, modifier: Modifier = Modifier) {
    val lineColor = MaterialTheme.colorScheme.primary
    val fillColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
    val bgColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.05f)

    Canvas(modifier = modifier.background(bgColor)) {
        if (data.size < 2) return@Canvas

        val w = size.width
        val h = size.height
        val stepX = w / (data.size - 1).coerceAtLeast(1)
        val padding = 4f

        // Build path
        val linePath = androidx.compose.ui.graphics.Path().apply {
            data.forEachIndexed { i, value ->
                val x = i * stepX
                val y = h - padding - (value * (h - padding * 2))
                if (i == 0) moveTo(x, y) else lineTo(x, y)
            }
        }

        // Fill path (closed to bottom)
        val fillPath = androidx.compose.ui.graphics.Path().apply {
            addPath(linePath)
            lineTo((data.size - 1) * stepX, h)
            lineTo(0f, h)
            close()
        }

        drawPath(fillPath, color = fillColor)
        drawPath(linePath, color = lineColor, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.5f, cap = StrokeCap.Round))
    }
}

// ── Helpers ──

@Composable
private fun formatTimeAgo(timestamp: Long, now: Long): String {
    val diff = now - timestamp
    val minutes = (diff / 60_000).toInt()
    val hours = (diff / 3_600_000).toInt()
    return when {
        minutes < 1 -> stringResource(R.string.time_now)
        minutes < 60 -> stringResource(R.string.time_minutes, minutes)
        hours < 24 -> stringResource(R.string.time_hours, hours)
        else -> stringResource(R.string.time_days, hours / 24)
    }
}
