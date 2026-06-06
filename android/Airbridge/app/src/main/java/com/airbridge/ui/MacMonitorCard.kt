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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.Battery0Bar
import androidx.compose.material.icons.rounded.Battery1Bar
import androidx.compose.material.icons.rounded.Battery2Bar
import androidx.compose.material.icons.rounded.Battery3Bar
import androidx.compose.material.icons.rounded.Battery4Bar
import androidx.compose.material.icons.rounded.Battery5Bar
import androidx.compose.material.icons.rounded.Battery6Bar
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.BatteryFull
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.protocol.MacInfo
import kotlin.math.roundToInt

@Composable
fun MacMonitorCard(info: MacInfo, wallpaperBase64: String?, onDisconnect: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        val bitmap = remember(wallpaperBase64) {
            wallpaperBase64?.let {
                runCatching {
                    val bytes = Base64.decode(it, Base64.NO_WRAP)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
                }.getOrNull()
            }
        }

        Box(modifier = Modifier.fillMaxWidth().height(300.dp)) {
            if (bitmap != null) {
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().height(300.dp)
                )
            } else {
                Box(modifier = Modifier.fillMaxWidth().height(300.dp).background(MaterialTheme.colorScheme.primaryContainer))
            }
            Box(
                modifier = Modifier.fillMaxWidth().height(300.dp).background(
                    Brush.verticalGradient(0.4f to Color.Transparent, 1f to Color.Black.copy(alpha = 0.7f))
                )
            )
            Column(modifier = Modifier.align(Alignment.BottomStart).padding(16.dp)) {
                Text(info.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = Color.White)
                Text(
                    text = "${info.model} · ${info.chip}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.85f)
                )
            }
            if (info.batteryPercent in 0..100) {
                val powerLabel = when {
                    info.batteryCharging -> stringResource(R.string.power_charging)
                    info.onACPower -> stringResource(R.string.power_adapter)
                    else -> stringResource(R.string.power_battery)
                }
                val powerIcon = if (info.batteryCharging)
                    Icons.Rounded.BatteryChargingFull
                else
                    batteryIcon(info.batteryPercent)
                // Źródło zasilania — osobno, lewy górny róg
                Row(
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(12.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.Black.copy(alpha = 0.35f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "${stringResource(R.string.power_source)}: $powerLabel",
                        style = MaterialTheme.typography.labelLarge,
                        color = Color.White
                    )
                }
                // Bateria — prawy górny róg
                Row(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(12.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.Black.copy(alpha = 0.35f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(powerIcon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(5.dp))
                    Text("${info.batteryPercent}%", style = MaterialTheme.typography.labelLarge, color = Color.White)
                }
            }
        }

        Column(modifier = Modifier.padding(16.dp)) {
            barRow("CPU", "${info.cpuLoadPercent}%", info.cpuLoadPercent / 100f)
            Spacer(Modifier.size(14.dp))
            barRow("RAM", "${gb(info.usedRamBytes)} / ${gb(info.totalRamBytes)}", frac(info.usedRamBytes, info.totalRamBytes))
            Spacer(Modifier.size(14.dp))
            barRow(stringResource(R.string.mac_disk), "${gb(info.totalStorageBytes - info.freeStorageBytes)} / ${gb(info.totalStorageBytes)}", frac(info.totalStorageBytes - info.freeStorageBytes, info.totalStorageBytes))

            Spacer(Modifier.size(18.dp))
            FilledTonalButton(
                onClick = onDisconnect,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(50)
            ) {
                Icon(Icons.Rounded.LinkOff, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.disconnect), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun barRow(label: String, valueText: String, fraction: Float) {
    Column {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            Text(valueText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        }
        Spacer(Modifier.size(6.dp))
        LinearProgressIndicator(
            progress = { fraction.coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    }
}

private fun batteryIcon(p: Int): ImageVector = when {
    p >= 95 -> Icons.Rounded.BatteryFull
    p >= 80 -> Icons.Rounded.Battery6Bar
    p >= 60 -> Icons.Rounded.Battery5Bar
    p >= 45 -> Icons.Rounded.Battery4Bar
    p >= 30 -> Icons.Rounded.Battery3Bar
    p >= 20 -> Icons.Rounded.Battery2Bar
    p >= 10 -> Icons.Rounded.Battery1Bar
    else -> Icons.Rounded.Battery0Bar
}

private fun frac(used: Long, total: Long): Float = if (total > 0) (used.toFloat() / total) else 0f

private fun gb(bytes: Long): String {
    val g = bytes.toDouble() / 1_000_000_000.0
    return if (g >= 100) "${g.roundToInt()} GB" else "${(g * 10).roundToInt() / 10.0} GB"
}
