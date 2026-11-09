package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
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
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material3.FilledTonalIconToggleButton
import androidx.compose.material3.PlainTooltip
import androidx.compose.material3.TooltipAnchorPosition
import androidx.compose.material3.TooltipBox
import androidx.compose.material3.TooltipDefaults
import androidx.compose.material3.rememberTooltipState
import androidx.compose.material.icons.automirrored.rounded.AddToHomeScreen
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LocalContentColor
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.foundation.Canvas
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
 * Section header above a group of cards: titleMedium, aligned with the card
 * content (16 dp, the card's own content padding), 24 dp above, 8 dp below.
 */
@Composable
fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 8.dp)
    )
}

/**
 * Header block of a card that is its whole section: titleMedium on the card's
 * own content inset, so the title belongs to the card rather than the page.
 */
@Composable
fun CardHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp)
    )
}

// ── Quick actions ──────────────────────────────────────────────────────────

/** Five tiles for what the app is for: send a file, a photo, a scanned document, the clipboard, open the Mac screen. */
@Composable
fun QuickActionsRow(
    onSendFile: () -> Unit,
    onSendPhoto: () -> Unit,
    onScanDocument: () -> Unit,
    onSendClipboard: () -> Unit,
    onMacScreen: () -> Unit,
    macScreenEnabled: Boolean,
    modifier: Modifier = Modifier,
    /** False while there is no Mac to send to: the actions stay in place, disabled. */
    enabled: Boolean = true
) {
    // One card like "Appearance" in Settings: the title at the top, the four
    // actions as tonal icon buttons underneath. Icons only: labels do not
    // fit the row on the cover screen.
    PageCard(modifier = modifier.fillMaxWidth().padding(top = 16.dp)) {
        CardHeader(stringResource(R.string.home_section_quick_actions))
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            QuickAction(Icons.AutoMirrored.Rounded.InsertDriveFile, stringResource(R.string.quick_file), onSendFile, enabled = enabled)
            QuickAction(Icons.Rounded.Photo, stringResource(R.string.quick_photo), onSendPhoto, enabled = enabled)
            QuickAction(Icons.Rounded.DocumentScanner, stringResource(R.string.quick_scan), onScanDocument, enabled = enabled)
            QuickAction(Icons.Rounded.ContentPaste, stringResource(R.string.quick_clipboard), onSendClipboard, enabled = enabled)
            QuickAction(Icons.AutoMirrored.Rounded.ScreenShare, stringResource(R.string.quick_mac_screen), onMacScreen, enabled = enabled && macScreenEnabled)
        }
    }
}

@Composable
private fun QuickAction(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    // Medium size from the Expressive icon button scale; the label becomes
    // the content description.
    FilledTonalIconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(IconButtonDefaults.mediumContainerSize()),
        shapes = IconButtonDefaults.shapes()
    ) {
        Icon(icon, contentDescription = label, modifier = Modifier.size(IconButtonDefaults.mediumIconSize))
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
    Column(modifier = modifier.fillMaxWidth().padding(top = 16.dp)) {
        PageCard(modifier = Modifier.fillMaxWidth()) {
            CardHeader(stringResource(R.string.home_section_clipboard))
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
                    // An icon instead of a label, so the row never fights the
                    // button for width; the label stays as the description.
                    FilledTonalIconButton(
                        onClick = onSendClipboard,
                        enabled = enabled,
                        modifier = Modifier.size(IconButtonDefaults.mediumContainerSize()),
                        shapes = IconButtonDefaults.shapes()
                    ) {
                        Icon(Icons.AutoMirrored.Rounded.Send, contentDescription = stringResource(R.string.clipboard_send_now), modifier = Modifier.size(IconButtonDefaults.mediumIconSize))
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
 * Shown while the Mac reports the selected headphones on its side: which
 * headphones, where they play, and one button to bring them to this phone.
 *
 * Choreography, one event at a time:
 * - Appear / disappear: the card's height and opacity move together on the
 *   standard (non-bouncy) spatial spring; the content rides along with it.
 * - Tap: the button morphs to its checked shape and colour while its glyph
 *   crossfades to the loader; the status line changes in the same frame.
 * - Done: the loader becomes a check, the status says where the headphones
 *   went, the card holds for a beat and then collapses.
 * The card stays on screen from the tap until that collapse, even though the
 * Mac stops reporting the headphones as soon as it releases them.
 */
@OptIn(ExperimentalMaterial3Api::class) // TooltipBox and its position provider
@Composable
fun HeadphonesCard(viewModel: MainViewModel, modifier: Modifier = Modifier) {
    val macHeadphoneState by viewModel.macHeadphoneState.collectAsState()
    val handoffPhase by viewModel.headphoneHandoffPhase.collectAsState()
    var previousPhase by remember { mutableStateOf(handoffPhase) }
    var showSuccess by remember { mutableStateOf(false) }
    LaunchedEffect(handoffPhase) {
        val finishedMove = previousPhase == HandoffPhase.IN_PROGRESS && handoffPhase == HandoffPhase.IDLE
        previousPhase = handoffPhase
        // A lost connection also resets the phase to IDLE, but clears the Mac's
        // report first: that is not a success.
        if (finishedMove && viewModel.macHeadphoneState.value != null) {
            showSuccess = true
            try {
                delay(1_400)
                // Collapse straight from the check once the Mac's report agrees;
                // capped so the card can never hang on.
                withTimeoutOrNull(3_000) { viewModel.macHeadphoneState.first { it?.connected != true } }
            } finally {
                showSuccess = false
            }
        }
    }
    // The last name the Mac sent, so the title does not fall back to the
    // generic label while the card is collapsing after the move.
    var lastName by remember { mutableStateOf<String?>(null) }
    macHeadphoneState?.name?.ifBlank { null }?.let { lastName = it }

    val state = when {
        showSuccess -> TakeoverState.SUCCESS
        handoffPhase == HandoffPhase.IN_PROGRESS -> TakeoverState.IN_PROGRESS
        else -> TakeoverState.IDLE
    }
    val visible = macHeadphoneState?.connected == true || handoffPhase != HandoffPhase.IDLE || showSuccess

    // Size changes use the standard scheme: an expressive spring overshoots the
    // card's height, clipping its content and bouncing everything below it.
    val standard = MotionScheme.standard()
    val cardSize = standard.defaultSpatialSpec<IntSize>()
    val fadeInSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val fadeOutSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    // Small glyphs may bounce: at 20 dp a little overshoot reads as alive.
    val glyphScale = MaterialTheme.motionScheme.fastSpatialSpec<Float>()

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(fadeInSpec) + expandVertically(cardSize, expandFrom = Alignment.Top),
        exit = fadeOut(fadeOutSpec) + shrinkVertically(cardSize, shrinkTowards = Alignment.Top),
        modifier = modifier
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(top = 16.dp)) {
            PageCard(modifier = Modifier.fillMaxWidth()) {
                CardHeader(stringResource(R.string.home_section_headphones))
                // Sound playing on the Mac: the headphone glyph gives way to a live
                // wave; back to the glyph when it goes quiet or the move starts.
                val playing = macHeadphoneState?.audioActive == true && state == TakeoverState.IDLE
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.secondaryContainer, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        AnimatedContent(
                            targetState = playing,
                            transitionSpec = {
                                (fadeIn(fadeInSpec) + scaleIn(glyphScale, initialScale = 0.7f)) togetherWith
                                    fadeOut(fadeOutSpec) using SizeTransform(clip = false)
                            },
                            contentAlignment = Alignment.Center,
                            label = "headphoneGlyph"
                        ) { isPlaying ->
                            if (isPlaying) {
                                SoundWave(color = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.size(width = 22.dp, height = 16.dp))
                            } else {
                                Icon(Icons.Rounded.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.size(20.dp))
                            }
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            lastName ?: stringResource(R.string.settings_headphone_device),
                            style = MaterialTheme.typography.bodyLarge,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        // Status line crossfades in place: same slot, same height,
                        // changing together with the button.
                        val statusRes = when {
                            state == TakeoverState.SUCCESS -> R.string.headphones_moved
                            state == TakeoverState.IN_PROGRESS -> R.string.headphones_moving
                            macHeadphoneState?.audioActive == true -> R.string.headphones_on_mac
                            else -> R.string.headphones_connected_mac
                        }
                        AnimatedContent(
                            targetState = statusRes,
                            transitionSpec = { fadeIn(fadeInSpec) togetherWith fadeOut(fadeOutSpec) using SizeTransform(clip = false) },
                            label = "headphoneStatus"
                        ) { res ->
                            Text(
                                stringResource(res),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                    Spacer(Modifier.width(16.dp))
                    // Icon-only, like the clipboard's send button; the label lives in
                    // the tooltip and the content description. A toggle button, so
                    // the move itself is the native Expressive "checked" morph:
                    // round -> rounded square and tonal -> filled, on the tap.
                    // It never turns disabled, which would flash it grey mid-move.
                    val switchLabel = stringResource(R.string.headphones_switch_here)
                    TooltipBox(
                        positionProvider = TooltipDefaults.rememberTooltipPositionProvider(TooltipAnchorPosition.Above),
                        tooltip = { PlainTooltip { Text(switchLabel) } },
                        state = rememberTooltipState()
                    ) {
                        FilledTonalIconToggleButton(
                            checked = state != TakeoverState.IDLE,
                            onCheckedChange = { if (state == TakeoverState.IDLE) viewModel.takeoverHeadphones() },
                            shapes = IconButtonDefaults.toggleableShapes(),
                            modifier = Modifier
                                .size(IconButtonDefaults.mediumContainerSize())
                                .semantics { contentDescription = switchLabel }
                        ) {
                            // Glyph -> loader -> check, in the button's own slot.
                            // The loader arrives with the morph; the check pops in
                            // with a small overshoot as the move lands.
                            AnimatedContent(
                                targetState = state,
                                transitionSpec = {
                                    (fadeIn(fadeInSpec) + scaleIn(glyphScale, initialScale = 0.6f)) togetherWith
                                        fadeOut(fadeOutSpec) using SizeTransform(clip = false)
                                },
                                contentAlignment = Alignment.Center,
                                label = "headphoneTakeover"
                            ) { s ->
                                when (s) {
                                    TakeoverState.SUCCESS -> Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(IconButtonDefaults.mediumIconSize))
                                    TakeoverState.IN_PROGRESS -> LoadingIndicator(modifier = Modifier.size(32.dp), color = LocalContentColor.current)
                                    TakeoverState.IDLE -> Icon(Icons.AutoMirrored.Rounded.AddToHomeScreen, contentDescription = null, modifier = Modifier.size(IconButtonDefaults.mediumIconSize))
                                }
                            }
                        }
                    }
                }
                AnimatedVisibility(
                    visible = handoffPhase == HandoffPhase.FAILED,
                    enter = fadeIn(fadeInSpec) + expandVertically(cardSize),
                    exit = fadeOut(fadeOutSpec) + shrinkVertically(cardSize)
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
