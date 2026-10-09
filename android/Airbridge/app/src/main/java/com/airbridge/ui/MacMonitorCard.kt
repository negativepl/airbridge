package com.airbridge.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.BatteryFull
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.BuildConfig
import com.airbridge.R
import com.airbridge.protocol.MacInfo
import kotlin.math.roundToInt

/**
 * Connected Mac: a stock media card. The wallpaper is the media (16:9, no
 * scrim, no text over it); the header block below carries the name, the
 * battery line and the guarded disconnect action. Live resource rings live in
 * [MacMonitorRings].
 */
@Composable
fun MacDeviceCard(
    info: MacInfo,
    wallpaperBase64: String?,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showDisconnectConfirm by remember { mutableStateOf(false) }

    val bitmap = remember(wallpaperBase64) {
        wallpaperBase64?.let {
            runCatching {
                val bytes = Base64.decode(it, Base64.NO_WRAP)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }?.asImageBitmap()
    }
    val mismatch = isVersionMismatch(info.appVersion, BuildConfig.VERSION_NAME)

    Column(modifier = modifier.fillMaxWidth()) {
        SectionTitle(stringResource(R.string.home_section_connected_device))
        Card(modifier = Modifier.fillMaxWidth()) {
            // Media: same size with or without a wallpaper, so the card does
            // not jump when the picture arrives.
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f)
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f)
                        .background(MaterialTheme.colorScheme.primaryContainer)
                )
            }
            // Header block: headline, supporting text, trailing action.
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = info.name,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (info.batteryPercent >= 0) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = if (info.batteryCharging) Icons.Rounded.BatteryChargingFull
                                              else Icons.Rounded.BatteryFull,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.size(4.dp))
                            Text(
                                text = batteryLine(info),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                    if (mismatch) {
                        Text(
                            text = stringResource(R.string.update_version_mismatch, info.appVersion),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                }
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { showDisconnectConfirm = true }) {
                    Icon(
                        Icons.Rounded.LinkOff,
                        contentDescription = stringResource(R.string.disconnect)
                    )
                }
            }
        }
    }

    if (showDisconnectConfirm) {
        AlertDialog(
            onDismissRequest = { showDisconnectConfirm = false },
            title = { Text(stringResource(R.string.disconnect)) },
            text = { Text(stringResource(R.string.home_disconnect_confirm, info.name)) },
            confirmButton = {
                TextButton(onClick = {
                    showDisconnectConfirm = false
                    onDisconnect()
                }) {
                    Text(stringResource(R.string.disconnect))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisconnectConfirm = false }) {
                    Text(stringResource(R.string.send_confirm_cancel))
                }
            }
        )
    }
}

/** Jedna linia o baterii Maca: "%", a przy ładowaniu czas do pełna gdy znany. */
@Composable
private fun batteryLine(info: MacInfo): String {
    if (!info.batteryCharging) return stringResource(R.string.home_battery_percent, info.batteryPercent)
    val ms = info.chargeTimeRemainingMs
    if (ms <= 0) return stringResource(R.string.home_battery_charging, info.batteryPercent)
    val totalMin = (ms / 60_000L).toInt()
    val h = totalMin / 60
    val m = totalMin % 60
    return if (h > 0) stringResource(R.string.home_battery_to_full_hm, info.batteryPercent, h, m)
    else stringResource(R.string.home_battery_to_full_m, info.batteryPercent, totalMin)
}

/**
 * True when both sides reported a (non-empty) app version and their base
 * versions differ, ignoring a "-beta"/"-alpha" suffix. Purely a comparison of
 * versions already exchanged over the LAN — no update-server traffic.
 */
internal fun isVersionMismatch(remoteVersion: String, localVersion: String): Boolean =
    remoteVersion.isNotEmpty() && localVersion.isNotEmpty() &&
        versionBase(remoteVersion) != versionBase(localVersion)

private fun versionBase(version: String): String = version.substringBefore("-")

/** Live CPU/RAM/disk rings for the connected Mac. */
/** [info] null (not connected yet): the three rings sit empty with "–" in place of numbers. */
@Composable
fun MacMonitorRings(info: MacInfo?, modifier: Modifier = Modifier) {
    Card(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            if (info == null) {
                MonitorRing(0f, "–", stringResource(R.string.home_monitor_cpu), null)
                MonitorRing(0f, "–", stringResource(R.string.home_monitor_ram), null)
                MonitorRing(0f, "–", stringResource(R.string.home_monitor_disk), null)
            } else {
            MonitorRing(
                fraction = info.cpuLoadPercent / 100f,
                centerText = "${info.cpuLoadPercent}%",
                label = stringResource(R.string.home_monitor_cpu),
                detail = if (info.cpuCores > 0) pluralStringResource(R.plurals.home_monitor_cores, info.cpuCores, info.cpuCores) else null
            )
            MonitorRing(
                fraction = frac(info.usedRamBytes, info.totalRamBytes),
                centerText = "${(frac(info.usedRamBytes, info.totalRamBytes) * 100).roundToInt()}%",
                label = stringResource(R.string.home_monitor_ram),
                detail = "${gb(info.usedRamBytes)} / ${gb(info.totalRamBytes)}"
            )
            val usedStorage = info.totalStorageBytes - info.freeStorageBytes
            MonitorRing(
                fraction = frac(usedStorage, info.totalStorageBytes),
                centerText = "${(frac(usedStorage, info.totalStorageBytes) * 100).roundToInt()}%",
                label = stringResource(R.string.home_monitor_disk),
                detail = "${gb(usedStorage)} / ${gb(info.totalStorageBytes)}"
            )
            }
        }
    }
}

@Composable
private fun MonitorRing(fraction: Float, centerText: String, label: String, detail: String?) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                progress = { fraction.coerceIn(0f, 1f) },
                modifier = Modifier.size(56.dp),
                strokeWidth = 5.dp,
                trackColor = MaterialTheme.colorScheme.surfaceContainerHigh
            )
            Text(centerText, style = MaterialTheme.typography.labelMedium)
        }
        Spacer(Modifier.height(6.dp))
        Text(label, style = MaterialTheme.typography.labelMedium)
        if (detail != null) {
            Text(
                text = detail,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun frac(used: Long, total: Long): Float = if (total > 0) (used.toFloat() / total) else 0f

private fun gb(bytes: Long): String {
    val g = bytes.toDouble() / 1_000_000_000.0
    return if (g >= 100) "${g.roundToInt()} GB" else "${(g * 10).roundToInt() / 10.0} GB"
}
