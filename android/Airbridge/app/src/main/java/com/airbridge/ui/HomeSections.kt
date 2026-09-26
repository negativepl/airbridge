package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.ScreenShare
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.Path
import androidx.compose.animation.core.LinearEasing
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.foundation.Canvas
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.EaseInOutSine
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.ActivityItem
import com.airbridge.service.HandoffPhase
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Section title used on every screen: text colour (not the accent), 16 sp
 * semibold, sitting close to its card.
 */
@Composable
fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleLarge,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 10.dp, top = 26.dp, bottom = 8.dp)
    )
}

// ── Quick actions ──────────────────────────────────────────────────────────

/** Four tiles for what the app is for: send a file, a photo, the clipboard, open the Mac screen. */
@Composable
fun QuickActionsRow(
    onSendFile: () -> Unit,
    onSendPhoto: () -> Unit,
    onSendClipboard: () -> Unit,
    onMacScreen: () -> Unit,
    macScreenEnabled: Boolean,
    modifier: Modifier = Modifier,
    /** False while there is no Mac to send to: the tiles stay in place, dimmed. */
    enabled: Boolean = true
) {
    Column(modifier = modifier.fillMaxWidth()) {
        SectionTitle(stringResource(R.string.home_section_quick_actions))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            QuickTile(Icons.AutoMirrored.Rounded.InsertDriveFile, stringResource(R.string.quick_file), onSendFile, enabled = enabled, modifier = Modifier.weight(1f))
            QuickTile(Icons.Rounded.Photo, stringResource(R.string.quick_photo), onSendPhoto, enabled = enabled, modifier = Modifier.weight(1f))
            QuickTile(Icons.Rounded.ContentPaste, stringResource(R.string.quick_clipboard), onSendClipboard, enabled = enabled, modifier = Modifier.weight(1f))
            QuickTile(Icons.AutoMirrored.Rounded.ScreenShare, stringResource(R.string.quick_mac_screen), onMacScreen, enabled = enabled && macScreenEnabled, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun QuickTile(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    AirbridgeCard(
        onClick = { if (enabled) onClick() },
        modifier = modifier.alpha(if (enabled) 1f else 0.5f),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp, horizontal = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(20.dp))
            }
            Spacer(Modifier.height(8.dp))
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center
            )
        }
    }
}

// ── Clipboard ──────────────────────────────────────────────────────────────

/**
 * The last clipboard sync (direction and time; the text itself is never stored)
 * and a button that sends the current clipboard to the Mac.
 */
@Composable
fun ClipboardCard(items: List<ActivityItem>, onSendClipboard: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val last = remember(items) { items.firstOrNull { it.type == "clipboard_sent" || it.type == "clipboard_received" } }
    val now = System.currentTimeMillis()
    Column(modifier = modifier.fillMaxWidth()) {
        SectionTitle(stringResource(R.string.home_section_clipboard))
        AirbridgeCard(
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.extraLarge,
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
        ) {
            ListItem(
                leadingContent = {
                    Box(
                        modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.secondaryContainer, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Rounded.ContentPaste, contentDescription = null, tint = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.size(20.dp))
                    }
                },
                content = {
                    Text(
                        when {
                            last == null -> stringResource(R.string.clipboard_never)
                            last.type == "clipboard_sent" -> stringResource(R.string.clipboard_last_sent)
                            else -> stringResource(R.string.clipboard_last_received)
                        }
                    )
                },
                supportingContent = last?.let { { Text(formatTimeAgo(it.timestamp, now)) } },
                trailingContent = {
                    FilledTonalButton(onClick = onSendClipboard, enabled = enabled) {
                        Text(stringResource(R.string.clipboard_send_now))
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
            )
        }
    }
}

// ── Headphones ─────────────────────────────────────────────────────────────

private enum class TakeoverState { IDLE, IN_PROGRESS, SUCCESS }

/**
 * Shown only while the Mac reports the selected headphones on its side: which
 * headphones, where they play, and one button to bring them to this phone.
 */
@Composable
fun HeadphonesCard(viewModel: MainViewModel, modifier: Modifier = Modifier) {
    val macHeadphoneState by viewModel.macHeadphoneState.collectAsState()
    val handoffPhase by viewModel.headphoneHandoffPhase.collectAsState()
    var lastHandoffPhase by remember { mutableStateOf(handoffPhase) }
    var showSuccess by remember { mutableStateOf(false) }
    LaunchedEffect(handoffPhase) {
        if (lastHandoffPhase == HandoffPhase.IN_PROGRESS && handoffPhase == HandoffPhase.IDLE) {
            showSuccess = true
            delay(1600)
            // Hold the checkmark until the Mac's own report catches up, so the card
            // collapses straight from the success state. Capped so it can never hang.
            withTimeoutOrNull(3_400) { viewModel.macHeadphoneState.first { it?.connected != true } }
            showSuccess = false
        }
        lastHandoffPhase = handoffPhase
    }
    val enterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val enterSize = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()
    val exitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val enterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val enterSizeInt = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
    val state = when {
        showSuccess -> TakeoverState.SUCCESS
        handoffPhase == HandoffPhase.IN_PROGRESS -> TakeoverState.IN_PROGRESS
        else -> TakeoverState.IDLE
    }

    AnimatedVisibility(
        visible = macHeadphoneState?.connected == true || showSuccess,
        enter = fadeIn(enterFade) + expandVertically(enterSize),
        exit = fadeOut(exitFade) + shrinkVertically(enterSize),
        modifier = modifier
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            SectionTitle(stringResource(R.string.home_section_headphones))
            AirbridgeCard(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
            ) {
                // Sound playing on the Mac: the headphone glyph gives way to a live
                // wave; back to the glyph when it goes quiet.
                val playing = macHeadphoneState?.audioActive == true && state == TakeoverState.IDLE
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        AnimatedContent(
                            targetState = playing,
                            transitionSpec = {
                                (fadeIn(enterFade) + scaleIn(initialScale = 0.7f, animationSpec = enterScale)) togetherWith
                                    (fadeOut(exitFade) + scaleOut(targetScale = 0.7f, animationSpec = exitFade))
                            },
                            label = "headphoneGlyph"
                        ) { isPlaying ->
                            if (isPlaying) {
                                SoundWave(color = MaterialTheme.colorScheme.onTertiaryContainer, modifier = Modifier.size(width = 22.dp, height = 16.dp))
                            } else {
                                Icon(Icons.Rounded.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.onTertiaryContainer, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            macHeadphoneState?.name?.ifBlank { null } ?: stringResource(R.string.settings_headphone_device),
                            style = MaterialTheme.typography.bodyLarge,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        // Status line: playing / connected but quiet / moved here. Swapped
                        // with a short fade and vertical slide instead of a hard cut.
                        val statusRes = when {
                            state == TakeoverState.SUCCESS -> R.string.headphones_moved
                            macHeadphoneState?.audioActive == true -> R.string.headphones_on_mac
                            else -> R.string.headphones_connected_mac
                        }
                        AnimatedContent(
                            targetState = statusRes,
                            transitionSpec = {
                                (fadeIn(enterFade) + slideInVertically(enterSizeInt) { it / 2 }) togetherWith
                                    (fadeOut(exitFade) + slideOutVertically(enterSizeInt) { -it / 2 })
                            },
                            label = "headphoneStatus"
                        ) { res ->
                            Text(stringResource(res), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    FilledTonalButton(
                        onClick = { viewModel.takeoverHeadphones() },
                        enabled = state == TakeoverState.IDLE
                    ) {
                        AnimatedContent(
                            targetState = state,
                            transitionSpec = {
                                (fadeIn(enterFade) + scaleIn(initialScale = 0.9f, animationSpec = enterScale)) togetherWith fadeOut(exitFade)
                            },
                            label = "headphoneTakeover"
                        ) { s ->
                            when (s) {
                                TakeoverState.SUCCESS -> Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                                TakeoverState.IN_PROGRESS -> LoadingIndicator(modifier = Modifier.size(18.dp))
                                TakeoverState.IDLE -> Text(stringResource(R.string.headphones_switch_here))
                            }
                        }
                    }
                }
                AnimatedVisibility(
                    visible = handoffPhase == HandoffPhase.FAILED,
                    enter = fadeIn(enterFade) + expandVertically(enterSize),
                    exit = fadeOut(exitFade) + shrinkVertically(enterSize)
                ) {
                    Text(
                        text = stringResource(R.string.headphone_takeover_failed),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp)
                    )
                }
            }
        }
    }
}

/**
 * A sine wave sliding along, its amplitude breathing: "sound is playing" as a
 * single stroke rather than a level meter.
 */
@Composable
private fun SoundWave(color: Color, modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "soundWave")
    val phase by transition.animateFloat(
        initialValue = 0f, targetValue = (2 * Math.PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(1_100, easing = LinearEasing)),
        label = "phase"
    )
    val breath by transition.animateFloat(
        initialValue = 0.55f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900, easing = EaseInOutSine), RepeatMode.Reverse),
        label = "breath"
    )
    val stroke = with(LocalDensity.current) { 2.dp.toPx() }
    Canvas(modifier = modifier) {
        val midY = size.height / 2f
        val amp = (size.height / 2f - stroke) * breath
        val path = Path()
        val steps = 32
        for (i in 0..steps) {
            val x = size.width * i / steps
            // Two full waves across the width; edges taper so the ends sit on the axis.
            val taper = kotlin.math.sin(Math.PI * i / steps).toFloat()
            val y = midY + amp * taper * kotlin.math.sin(2 * 2 * Math.PI * i / steps + phase).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color = color, style = Stroke(width = stroke, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}
