package com.airbridge.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DesktopWindows
import androidx.compose.material.icons.rounded.PhoneAndroid
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.airbridge.R

@Composable
fun ScreenShareScreen(bottomClearance: Dp = 88.dp, topInset: Dp = 0.dp) {
    val mirror = rememberMirrorLauncher()
    val ready = mirror.ready
    fun launch(mode: Int) = mirror.launch(mode)

    // Two modes, one feature card each: icon tile, title, detail, Start.
    // bottomClearance keeps the content clear of the floating FAB.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = 16.dp, end = 16.dp, top = topInset + 16.dp, bottom = bottomClearance),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (ready) {
            ModeCard(
                icon = Icons.Rounded.DesktopWindows,
                title = stringResource(R.string.screen_sharing_show_mac),
                subtitle = stringResource(R.string.screen_sharing_show_mac_desc),
                onClick = { launch(0) }
            )
            ModeCard(
                icon = Icons.Rounded.PhoneAndroid,
                title = stringResource(R.string.screen_sharing_second_display),
                subtitle = stringResource(R.string.screen_sharing_second_display_desc),
                onClick = { launch(1) }
            )
        } else {
            NotConnected(modifier = Modifier.weight(1f))
        }
    }
}

/**
 * One display mode as a feature card: a tonal icon tile, the title, the
 * detail and a Start button. The whole card opens the mode as well.
 */
@Composable
private fun ModeCard(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    PageCard(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp)) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .background(MaterialTheme.colorScheme.primaryContainer, MaterialTheme.shapes.large),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(28.dp))
            }
            Spacer(Modifier.size(16.dp))
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(Modifier.size(4.dp))
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.size(16.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(onClick = onClick, shapes = ButtonDefaults.shapes()) {
                    Text(stringResource(R.string.screen_sharing_start))
                }
            }
        }
    }
}

@Composable
private fun NotConnected(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(MaterialShapes.Flower.toShape())
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Rounded.DesktopWindows,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(36.dp)
            )
        }
        Spacer(Modifier.size(16.dp))
        Text(
            stringResource(R.string.screen_sharing_connect_first),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}
