package com.airbridge.ui

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.airbridge.mirror.ReverseMirrorActivity
import com.airbridge.security.KeyManager
import com.airbridge.service.AirbridgeService

/** Opens the Mac screen mirror (mode 0) or the virtual second display (mode 1). */
class MirrorLauncher(val ready: Boolean, private val start: (Int) -> Unit) {
    fun launch(mode: Int) = start(mode)
}

/**
 * Shared by the Screen tab and the home quick actions. The mirror hello token
 * is this phone's own Ed25519 public-key prefix (16 bytes), which the Mac
 * validates against the paired device.
 */
@Composable
fun rememberMirrorLauncher(): MirrorLauncher {
    val context = LocalContext.current
    val isConnected by AirbridgeService.isConnected.collectAsState()
    val host by AirbridgeService.connectedHost.collectAsState()
    val mirrorPort by AirbridgeService.mirrorPortFlow.collectAsState()
    val token = remember {
        runCatching { KeyManager(context).getRawPublicKeyBytes().copyOf(16) }.getOrNull()
    }
    val ready = isConnected && host != null && mirrorPort != null && token != null
    return MirrorLauncher(ready) { mode ->
        val h = host ?: return@MirrorLauncher
        val p = mirrorPort ?: return@MirrorLauncher
        val t = token ?: return@MirrorLauncher
        val intent = Intent(context, ReverseMirrorActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(ReverseMirrorActivity.EXTRA_HOST, h)
            putExtra(ReverseMirrorActivity.EXTRA_PORT, p)
            putExtra(ReverseMirrorActivity.EXTRA_TOKEN, t)
            putExtra(ReverseMirrorActivity.EXTRA_MODE, mode)
            putExtra(ReverseMirrorActivity.EXTRA_CERT_FINGERPRINT, AirbridgeService.certFingerprintInUse())
        }
        context.startActivity(intent)
    }
}
