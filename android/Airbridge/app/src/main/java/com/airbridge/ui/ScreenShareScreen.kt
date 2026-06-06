package com.airbridge.ui

import android.content.Context
import android.content.Intent
import android.util.Base64
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.DesktopWindows
import androidx.compose.material.icons.rounded.PhoneIphone
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.mirror.ReverseMirrorActivity
import com.airbridge.service.AirbridgeService

@Composable
fun ScreenShareScreen() {
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
        }
        context.startActivity(intent)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
    ) {
        Spacer(Modifier.size(16.dp))
        Text(
            text = stringResource(R.string.screen_sharing_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.size(16.dp))

        if (ready) {
            shareCard(
                icon = Icons.Rounded.DesktopWindows,
                title = stringResource(R.string.screen_sharing_show_mac),
                subtitle = stringResource(R.string.screen_sharing_show_mac_desc),
                onClick = { launch(0) }
            )
            Spacer(Modifier.size(12.dp))
            shareCard(
                icon = Icons.Rounded.PhoneIphone,
                title = stringResource(R.string.screen_sharing_second_display),
                subtitle = stringResource(R.string.screen_sharing_second_display_desc),
                onClick = { launch(1) }
            )
        } else {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
            ) {
                Text(
                    text = stringResource(R.string.screen_sharing_connect_first),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(20.dp)
                )
            }
        }
    }
}

@Composable
private fun shareCard(icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(18.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Start
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(28.dp)
            )
            Spacer(Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
                Spacer(Modifier.size(2.dp))
                Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(
                Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
