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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LaptopMac
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.BuildConfig
import com.airbridge.R
import com.airbridge.protocol.MacInfo
import kotlin.math.roundToInt

/**
 * Compact Mac identity card: wallpaper thumbnail, name, connection/battery
 * status, and a disconnect action. Replaces the old wallpaper-hero monolith —
 * live resource bars now live in [MacMonitorRings].
 */
@Composable
fun MacDeviceCard(
    info: MacInfo,
    wallpaperBase64: String?,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
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

        var menuExpanded by remember { mutableStateOf(false) }

        ListItem(
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            leadingContent = {
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(56.dp)
                            .clip(MaterialTheme.shapes.large)
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .size(56.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.surfaceContainer),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.LaptopMac,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }
            },
            headlineContent = {
                Text(
                    text = info.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            },
            supportingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF34C759))
                    )
                    Spacer(Modifier.size(6.dp))
                    val statusText = stringResource(R.string.home_connected_battery, info.batteryPercent).let {
                        if (info.batteryCharging) "$it · ${stringResource(R.string.power_charging)}" else it
                    }
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            },
            trailingContent = {
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(
                        expanded = menuExpanded,
                        onDismissRequest = { menuExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.disconnect)) },
                            onClick = {
                                menuExpanded = false
                                onDisconnect()
                            }
                        )
                    }
                }
            }
        )

        if (isVersionMismatch(info.appVersion, BuildConfig.VERSION_NAME)) {
            Text(
                text = stringResource(R.string.update_version_mismatch, info.appVersion),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.tertiary,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
            )
        }
    }
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
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Text(
            text = stringResource(R.string.home_monitor_title).uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 12.dp)
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            MonitorRing(
                fraction = info.cpuLoadPercent / 100f,
                centerText = "${info.cpuLoadPercent}%",
                label = stringResource(R.string.home_monitor_cpu),
                detail = null
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
