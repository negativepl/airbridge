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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.EaseInOutSine
import android.provider.Settings
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.runtime.mutableIntStateOf
import android.os.Build
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.draw.drawBehind
import android.graphics.Bitmap
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

    val decoded = remember(wallpaperBase64) {
        wallpaperBase64?.let {
            runCatching {
                val bytes = Base64.decode(it, Base64.NO_WRAP)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }
    val bitmap = remember(decoded) { decoded?.asImageBitmap() }
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val blurSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    val glowColors = remember(decoded, blurSupported) {
        if (blurSupported) null else decoded?.let(::wallpaperGlowColors)
    }
    var cardHeightPx by remember { mutableIntStateOf(0) }

    Box(modifier = modifier.fillMaxWidth()) {
        // The wallpaper itself, blurred at full resolution (RenderEffect), drawn
        // behind the card and spilling GLOW_HEIGHT below it, faded out at the
        // bottom. Below API 31 there is no RenderEffect; a colour glow stands in.
        if (bitmap != null && blurSupported && cardHeightPx > 0) {
            WallpaperSpill(bitmap = bitmap, cardHeightPx = cardHeightPx, alpha = if (dark) 0.65f else 0.55f)
        }
        AirbridgeCard(
            modifier = Modifier
                .fillMaxWidth()
                .onSizeChanged { cardHeightPx = it.height }
                .wallpaperGlow(glowColors, alpha = if (dark) 0.45f else 0.30f),
            shape = MaterialTheme.shapes.extraLarge,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
        ) {

        Box(modifier = Modifier.fillMaxWidth().height(200.dp)) {
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

/**
 * Three colours the wallpaper's lower third averages to (left, centre,
 * right), nudged towards saturation so the glow keeps the picture's hue
 * rather than its muddy mean.
 */
private fun wallpaperGlowColors(bitmap: Bitmap): List<Color> {
    val top = bitmap.height * 2 / 3
    val band = Bitmap.createBitmap(bitmap, 0, top, bitmap.width, bitmap.height - top)
    val samples = Bitmap.createScaledBitmap(band, 3, 1, true)
    return (0 until 3).map { x ->
        val hsv = FloatArray(3)
        android.graphics.Color.colorToHSV(samples.getPixel(x, 0), hsv)
        hsv[1] = hsv[1].coerceAtLeast(0.45f)
        hsv[2] = hsv[2].coerceIn(0.55f, 0.9f)
        Color(android.graphics.Color.HSVToColor(hsv))
    }
}

/**
 * Light spilling from the wallpaper onto the background below the card: a
 * horizontal blend of [colors] masked by a wide ellipse centred on the card's
 * bottom edge, so it fades out smoothly downwards and to the sides. Drawn
 * behind the card, so only the spill is visible.
 */
private fun Modifier.wallpaperGlow(colors: List<Color>?, alpha: Float): Modifier {
    if (colors == null) return this
    return drawBehind {
        val glow = GLOW_HEIGHT.toPx()
        val rect = Rect(0f, size.height * 0.5f, size.width, size.height + glow)
        drawContext.canvas.saveLayer(rect, Paint())
        drawRect(
            brush = Brush.horizontalGradient(colors),
            topLeft = rect.topLeft,
            size = rect.size,
            alpha = alpha
        )
        // Elliptical alpha mask: a circle of radius glow, stretched to 1.4x the
        // card width, centred on the bottom edge.
        val centre = Offset(size.width / 2f, size.height)
        val sx = size.width * 0.7f / glow
        scale(scaleX = sx, scaleY = 1f, pivot = centre) {
            drawRect(
                brush = Brush.radialGradient(
                    0f to Color.Black, 1f to Color.Transparent,
                    center = centre, radius = glow
                ),
                topLeft = rect.topLeft,
                size = rect.size,
                blendMode = BlendMode.DstIn
            )
        }
        drawContext.canvas.restore()
    }
}

private val GLOW_HEIGHT = 180.dp
// Reach of the light past the card: tighter above (the top bar is close), wider elsewhere.
private val SPILL = 28.dp
private val SPILL_TOP = 30.dp

/**
 * Ambilight: the blurred wallpaper centred behind the card and reaching
 * SPILL past every edge. Laid out larger than the card but reported as zero
 * size, so it takes no room in the column; an alpha mask fades it out
 * towards its own edges so the light pools around the card.
 */
@Composable
private fun WallpaperSpill(bitmap: ImageBitmap, cardHeightPx: Int, alpha: Float) {
    // A barely-there drift: the light breathes (2% scale) and sways a few dp
    // sideways over ~9 s, so it reads as light rather than a printed halo.
    // Skipped when the system has animations turned off.
    val animationsOn = LocalContext.current.let {
        Settings.Global.getFloat(it.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
    }
    val drift = rememberInfiniteTransition(label = "ambilight")
    val phase by drift.animateFloat(
        initialValue = 0f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(9_000, easing = EaseInOutSine), RepeatMode.Reverse),
        label = "ambilightPhase"
    )
    val sway = with(LocalDensity.current) { 6.dp.toPx() }
    // The light fades in over ~0.6 s once the wallpaper is here instead of popping.
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val shownAlpha by animateFloatAsState(
        targetValue = if (appeared) alpha else 0f,
        animationSpec = tween(600, easing = EaseInOutSine),
        label = "ambilightAlpha"
    )
    Image(
        bitmap = bitmap,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = Modifier
            .layout { measurable, constraints ->
                val spill = SPILL.roundToPx()
                val top = SPILL_TOP.roundToPx()
                val placeable = measurable.measure(
                    Constraints.fixed(constraints.maxWidth + 2 * spill, cardHeightPx + top + spill)
                )
                layout(constraints.maxWidth, 0) { placeable.place(-spill, -top) }
            }
            .graphicsLayer {
                compositingStrategy = CompositingStrategy.Offscreen
                if (animationsOn) {
                    val t = phase * 2f - 1f  // -1..1
                    scaleX = 1.02f + 0.02f * t
                    scaleY = 1.02f + 0.02f * t
                    translationX = sway * t
                }
            }
            .drawWithContent {
                drawContent()
                val fx = SPILL.toPx() / size.width
                val fyTop = SPILL_TOP.toPx() / size.height
                val fy = SPILL.toPx() / size.height
                val on = Color.Black.copy(alpha = shownAlpha)
                drawRect(
                    brush = Brush.verticalGradient(0f to Color.Transparent, fyTop to on, 1f - fy to on, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn
                )
                drawRect(
                    brush = Brush.horizontalGradient(0f to Color.Transparent, fx to Color.Black, 1f - fx to Color.Black, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn
                )
                // Round it off: dim towards the corners so the halo reads as light
                // pooling around the card, not a rectangle with soft edges.
                drawRect(
                    brush = Brush.radialGradient(
                        0f to Color.Black, 0.55f to Color.Black, 1f to Color.Black.copy(alpha = 0.1f),
                        center = Offset(size.width / 2f, size.height / 2f),
                        radius = kotlin.math.hypot(size.width / 2f, size.height / 2f)
                    ),
                    blendMode = BlendMode.DstIn
                )
            }
            .blur(48.dp, BlurredEdgeTreatment.Unbounded)
    )
}
