package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.DesktopMac
import androidx.compose.material.icons.rounded.LaptopMac
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.WarningAmber
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import com.airbridge.service.AirbridgeService
import com.airbridge.util.formatTransferSpeed
import androidx.compose.ui.unit.Dp
import kotlinx.coroutines.delay

@Composable
fun MainScreen(viewModel: MainViewModel, onScanQr: () -> Unit = {}, bottomClearance: Dp = 88.dp) {
    val isConnected by viewModel.isConnected.collectAsState()
    val connectedDeviceName by viewModel.connectedDeviceName.collectAsState()
    val transferProgress by viewModel.transferProgress.collectAsState()
    val transferFileName by viewModel.transferFileName.collectAsState()
    val transferSpeedBps by viewModel.transferSpeedBps.collectAsState()
    val transferEtaSeconds by viewModel.transferEtaSeconds.collectAsState()
    val transferSpeedHistory by viewModel.transferSpeedHistory.collectAsState()
    val stats by viewModel.stats.collectAsState()
    val activity by viewModel.recentActivity.collectAsState()

    val context = LocalContext.current
    val pairedDeviceStore = remember { com.airbridge.security.PairedDeviceStore(context) }
    val pairedDevicesRevision by com.airbridge.security.PairedDeviceStore.revision.collectAsState()
    val hasPairedDevices = remember(pairedDevicesRevision) { pairedDeviceStore.getAll().isNotEmpty() }

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
                onClick = { onScanQr() }
            ) {
                Text(stringResource(R.string.pairing_add_mac))
            }
        }
    } else {

    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 24.dp)
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // ── Device / Mac monitor ──
        val macInfo by AirbridgeService.macInfo.collectAsState()
        val macWallpaper by AirbridgeService.macWallpaper.collectAsState()

        // Live-refresh the Mac stats while connected.
        LaunchedEffect(isConnected) {
            while (isConnected) {
                AirbridgeService.requestMacInfo()
                delay(3000)
            }
        }

        val mac = macInfo
        // 2 = połączony z danymi Maca, 1 = łączenie (brak MacInfo), 0 = rozłączony.
        val connState = when {
            isConnected && mac != null -> 2
            isConnected -> 1
            else -> 0
        }
        val connEnterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
        val connEnterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
        val connExitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
        androidx.compose.animation.AnimatedContent(
            targetState = connState,
            transitionSpec = {
                (androidx.compose.animation.fadeIn(animationSpec = connEnterFade) +
                    androidx.compose.animation.scaleIn(
                        initialScale = 0.92f,
                        animationSpec = connEnterScale
                    )).togetherWith(
                    androidx.compose.animation.fadeOut(animationSpec = connExitFade)
                )
            },
            label = "connectionState"
        ) { state ->
            when (state) {
                2 -> {
                    val macLocal = macInfo
                    if (macLocal != null) {
                        MacMonitorCard(info = macLocal, wallpaperBase64 = macWallpaper, onDisconnect = { viewModel.disconnect() })
                    }
                }
                // Połączono, ale dane Maca jeszcze nie dotarły — spójny stan ładowania
                // zamiast błysku "połączonego" DeviceCard zanim przyjdzie MacInfo.
                1 -> ConnectingCard(deviceName = connectedDeviceName)
                else -> DeviceCard(
                    isConnected = isConnected,
                    deviceName = connectedDeviceName,
                    onDisconnect = { viewModel.disconnect() },
                    onReconnect = { viewModel.reconnect() }
                )
            }
        }

        // ── Re-pair guidance (TLS pin missing or Mac certificate changed) ──
        val pairingIssue by AirbridgeService.pairingIssue.collectAsState()
        androidx.compose.animation.AnimatedVisibility(
            visible = pairingIssue != null,
            enter = androidx.compose.animation.expandVertically() + androidx.compose.animation.fadeIn(),
            exit = androidx.compose.animation.shrinkVertically() + androidx.compose.animation.fadeOut()
        ) {
            Column {
                Spacer(modifier = Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.extraLarge,
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Rounded.WarningAmber,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onErrorContainer,
                                modifier = Modifier.size(24.dp)
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = pairingIssue ?: "",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                        }
                        // Direct path to the QR scanner from the warning, so the
                        // user does not have to find re-pairing on their own.
                        TextButton(
                            onClick = onScanQr,
                            modifier = Modifier.align(Alignment.End),
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.onErrorContainer
                            )
                        ) {
                            Text(stringResource(R.string.repair_action_scan))
                        }
                    }
                }
            }
        }

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
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primaryContainer
                )
            ) {
                Column(
                    modifier = Modifier
                        .padding(16.dp)
                        .animateContentSize(
                            animationSpec = MaterialTheme.motionScheme.defaultSpatialSpec()
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
                    LinearWavyProgressIndicator(
                        progress = { transferProgress ?: 0f },
                        modifier = Modifier.fillMaxWidth(),
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
                                    .clip(MaterialTheme.shapes.medium)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                        }

                        // Speed + ETA
                        val speedText = formatTransferSpeed(transferSpeedBps)
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
                        val speedText = formatTransferSpeed(transferSpeedBps)
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

        Spacer(Modifier.height(16.dp))
        StatsSection(stats)
        ActivityFeed(activity)

        // The FAB floats over the scroll content (Scaffold's innerPadding only
        // reserves the nav bar, not the FAB). The clearance is measured from the
        // real FAB and dock positions so the last row sits the same distance above
        // the FAB as the FAB sits above the dock.
        Spacer(modifier = Modifier.height(bottomClearance))
    }
    } // end else (hasPairedDevices)
}

// ── Device Card ──

@Composable
private fun ConnectingCard(deviceName: String?) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        tonalElevation = 2.dp,
        color = MaterialTheme.colorScheme.surfaceContainerLowest
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            LoadingIndicator(
                modifier = Modifier.size(64.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = stringResource(R.string.connecting),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            if (deviceName != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = deviceName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

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
        shape = MaterialTheme.shapes.extraLarge,
        tonalElevation = 2.dp,
        color = MaterialTheme.colorScheme.surfaceContainerLowest
    ) {
        val cardEnterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
        val cardEnterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
        val cardExitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
        androidx.compose.animation.AnimatedContent(
            targetState = state,
            transitionSpec = {
                (androidx.compose.animation.fadeIn(animationSpec = cardEnterFade) +
                    androidx.compose.animation.scaleIn(
                        initialScale = 0.95f,
                        animationSpec = cardEnterScale
                    )) togetherWith (androidx.compose.animation.fadeOut(animationSpec = cardExitFade))
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

                        androidx.compose.material3.FilledTonalButton(onClick = onDisconnect) {
                            Icon(
                                Icons.Rounded.LinkOff,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.disconnect))
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
                            LoadingIndicator(
                                modifier = Modifier.size(56.dp),
                                color = MaterialTheme.colorScheme.primary
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
                                .height(48.dp)
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

