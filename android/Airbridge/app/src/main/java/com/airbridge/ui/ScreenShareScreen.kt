package com.airbridge.ui

import android.content.Context
import android.content.Intent
import android.util.Base64
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DesktopWindows
import androidx.compose.material.icons.rounded.PhoneIphone
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.graphics.shapes.RoundedPolygon
import com.airbridge.R
import com.airbridge.mirror.ReverseMirrorActivity
import com.airbridge.service.AirbridgeService

@Composable
fun ScreenShareScreen(bottomClearance: Dp = 88.dp) {
    val context = LocalContext.current
    val isConnected by AirbridgeService.isConnected.collectAsState()
    val host by AirbridgeService.connectedHost.collectAsState()
    val mirrorPort by AirbridgeService.mirrorPortFlow.collectAsState()
    val token = remember(isConnected) {
        context.getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE).getString("mirror_token", null)
    }
    val ready = isConnected && host != null && mirrorPort != null && token != null

    fun launch(mode: Int) {
        val h = host ?: return
        val p = mirrorPort ?: return
        val t = token ?: return
        val intent = Intent(context, ReverseMirrorActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(ReverseMirrorActivity.EXTRA_HOST, h)
            putExtra(ReverseMirrorActivity.EXTRA_PORT, p)
            putExtra(ReverseMirrorActivity.EXTRA_TOKEN, Base64.decode(t, Base64.NO_WRAP))
            putExtra(ReverseMirrorActivity.EXTRA_MODE, mode)
            putExtra(ReverseMirrorActivity.EXTRA_CERT_FINGERPRINT, AirbridgeService.certFingerprintInUse())
        }
        context.startActivity(intent)
    }

    // Only two modes — render them as full-height tiles that split the screen so
    // the tab reads as a deliberate mode picker instead of two rows stranded at
    // the top. bottomClearance keeps the lower tile clear of the floating FAB.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = 24.dp, end = 24.dp, top = 8.dp, bottom = bottomClearance),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (ready) {
            ShareTile(
                polygon = MaterialShapes.Cookie9Sided,
                container = MaterialTheme.colorScheme.primaryContainer,
                onContainer = MaterialTheme.colorScheme.onPrimaryContainer,
                icon = Icons.Rounded.DesktopWindows,
                title = stringResource(R.string.screen_sharing_show_mac),
                subtitle = stringResource(R.string.screen_sharing_show_mac_desc),
                onClick = { launch(0) },
                modifier = Modifier.weight(1f)
            )
            ShareTile(
                polygon = MaterialShapes.Clover4Leaf,
                container = MaterialTheme.colorScheme.tertiaryContainer,
                onContainer = MaterialTheme.colorScheme.onTertiaryContainer,
                icon = Icons.Rounded.PhoneIphone,
                title = stringResource(R.string.screen_sharing_second_display),
                subtitle = stringResource(R.string.screen_sharing_second_display_desc),
                onClick = { launch(1) },
                modifier = Modifier.weight(1f)
            )
        } else {
            NotConnected(modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun ShareTile(
    polygon: RoundedPolygon,
    container: Color,
    onContainer: Color,
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)
    ) {
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(polygon.toShape())
                    .background(container),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = onContainer, modifier = Modifier.size(36.dp))
            }
            Spacer(Modifier.size(16.dp))
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center
            )
            Spacer(Modifier.size(4.dp))
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
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
