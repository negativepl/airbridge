package com.airbridge.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.BatteryFull
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.BuildConfig
import com.airbridge.R
import com.airbridge.protocol.MacInfo
import kotlin.math.roundToInt

/**
 * Mac identity banner: full-width wallpaper (same grammar as the paired-device
 * card in Settings), status pill top-left, guarded disconnect top-right, name +
 * battery bottom-left. Live resource rings live in [MacMonitorRings].
 */
@Composable
fun MacDeviceCard(
    info: MacInfo,
    wallpaperBase64: String?,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showDisconnectConfirm by remember { mutableStateOf(false) }

    AirbridgeCard(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        val bitmap = remember(wallpaperBase64) {
            wallpaperBase64?.let {
                runCatching {
                    val bytes = Base64.decode(it, Base64.NO_WRAP)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                }.getOrNull()
            }
        }

        Box(modifier = Modifier.fillMaxWidth().height(172.dp)) {
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize()
                )
            } else {
                Box(modifier = Modifier.matchParentSize().background(MaterialTheme.colorScheme.primaryContainer))
            }
            // Scrim na dole — czytelność nazwy i baterii na dowolnej tapecie.
            Box(
                modifier = Modifier.matchParentSize().background(
                    Brush.verticalGradient(0.4f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f))
                )
            )
            // Status — pigułka u góry po lewej, jak w Ustawieniach.
            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(12.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.35f))
                    .padding(horizontal = 10.dp, vertical = 5.dp)
            ) {
                Text(
                    stringResource(R.string.home_status_connected),
                    style = MaterialTheme.typography.labelLarge,
                    color = Color.White
                )
            }
            // Rozłączanie — wtopione w obraz i strzeżone potwierdzeniem, żeby
            // przypadkowy tap nie zrywał sesji.
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.Black.copy(alpha = 0.35f))
                    .clickable { showDisconnectConfirm = true }
                    .padding(8.dp)
            ) {
                Icon(
                    Icons.Rounded.LinkOff,
                    contentDescription = stringResource(R.string.disconnect),
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }
            Column(modifier = Modifier.align(Alignment.BottomStart).padding(16.dp)) {
                Text(
                    text = info.name,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (info.batteryPercent >= 0) {
                    Spacer(Modifier.height(2.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = if (info.batteryCharging) Icons.Rounded.BatteryChargingFull
                                          else Icons.Rounded.BatteryFull,
                            contentDescription = null,
                            tint = Color.White.copy(alpha = 0.9f),
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(Modifier.size(4.dp))
                        Text(
                            text = batteryLine(info),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.9f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        if (isVersionMismatch(info.appVersion, BuildConfig.VERSION_NAME)) {
            Text(
                text = stringResource(R.string.update_version_mismatch, info.appVersion),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.padding(16.dp)
            )
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
@Composable
fun MacMonitorRings(info: MacInfo, modifier: Modifier = Modifier) {
    AirbridgeCard(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
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
