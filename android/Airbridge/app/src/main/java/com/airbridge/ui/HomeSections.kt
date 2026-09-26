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
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(start = 4.dp, top = 18.dp, bottom = 6.dp)
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
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        SectionTitle(stringResource(R.string.home_section_quick_actions))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            QuickTile(Icons.AutoMirrored.Rounded.InsertDriveFile, stringResource(R.string.quick_file), onSendFile, modifier = Modifier.weight(1f))
            QuickTile(Icons.Rounded.Photo, stringResource(R.string.quick_photo), onSendPhoto, modifier = Modifier.weight(1f))
            QuickTile(Icons.Rounded.ContentPaste, stringResource(R.string.quick_clipboard), onSendClipboard, modifier = Modifier.weight(1f))
            QuickTile(Icons.AutoMirrored.Rounded.ScreenShare, stringResource(R.string.quick_mac_screen), onMacScreen, enabled = macScreenEnabled, modifier = Modifier.weight(1f))
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
fun ClipboardCard(items: List<ActivityItem>, onSendClipboard: () -> Unit, modifier: Modifier = Modifier) {
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
                    FilledTonalButton(onClick = onSendClipboard) {
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
                ListItem(
                    leadingContent = {
                        Box(
                            modifier = Modifier.size(40.dp).background(MaterialTheme.colorScheme.tertiaryContainer, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Rounded.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.onTertiaryContainer, modifier = Modifier.size(20.dp))
                        }
                    },
                    content = {
                        Text(
                            macHeadphoneState?.name?.ifBlank { null } ?: stringResource(R.string.settings_headphone_device),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    },
                    supportingContent = {
                        Text(stringResource(if (state == TakeoverState.SUCCESS) R.string.headphones_moved else R.string.headphones_on_mac))
                    },
                    trailingContent = {
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
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    when (s) {
                                        TakeoverState.SUCCESS -> Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                                        TakeoverState.IN_PROGRESS -> LoadingIndicator(modifier = Modifier.size(18.dp))
                                        TakeoverState.IDLE -> {
                                            Text(stringResource(R.string.headphones_switch_here))
                                        }
                                    }
                                    if (s != TakeoverState.IDLE) Spacer(Modifier.width(0.dp))
                                }
                            }
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                )
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
