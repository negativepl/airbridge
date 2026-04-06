package com.airbridge.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import com.airbridge.protocol.ContentType
import com.airbridge.service.ActivityItem
import com.airbridge.service.AirbridgeService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class MainViewModel(application: Application) : AndroidViewModel(application) {

    // Observe shared state from service
    val isConnected: StateFlow<Boolean> = AirbridgeService.isConnected
    val connectedDeviceName: StateFlow<String?> = AirbridgeService.connectedDeviceName
    val connectedHost: StateFlow<String?> = AirbridgeService.connectedHost
    val connectedSince: StateFlow<Long?> = AirbridgeService.connectedSince
    val recentActivity: StateFlow<List<ActivityItem>> = AirbridgeService.recentActivity
    val transferProgress: StateFlow<Float?> = AirbridgeService.transferProgress
    val transferFileName: StateFlow<String?> = AirbridgeService.transferFileName
    val transferSpeedBps: StateFlow<Long> = AirbridgeService.transferSpeedBps
    val transferEtaSeconds: StateFlow<Int> = AirbridgeService.transferEtaSeconds
    val transferSpeedHistory: StateFlow<List<Float>> = AirbridgeService.transferSpeedHistory

    private val _showQrScanner = MutableStateFlow(false)
    val showQrScanner: StateFlow<Boolean> = _showQrScanner.asStateFlow()

    fun startService() {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_START_DISCOVERY
        }
        getApplication<Application>().startForegroundService(intent)
    }

    fun stopService() {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_DISCONNECT
        }
        getApplication<Application>().startService(intent)
    }

    fun showQrScanner() {
        _showQrScanner.value = true
    }

    fun hideQrScanner() {
        _showQrScanner.value = false
    }

    fun onPaired(deviceName: String) {
        hideQrScanner()
    }

    fun disconnect() {
        stopService()
    }

    fun reconnect() {
        startService()
    }

    fun sendClipboard(text: String) {
        AirbridgeService.sendClipboardToMac(ContentType.PLAIN_TEXT, text)
    }

    fun sendPing() {
        AirbridgeService.sendPing()
    }

    fun sendFile(uri: Uri) {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_SEND_FILE
            data = uri
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        getApplication<Application>().startService(intent)
    }

    fun handlePairingPayload(payload: com.airbridge.pairing.PairingPayload) {
        val context = getApplication<Application>()
        val keyManager = com.airbridge.security.KeyManager(context)
        val pairedDeviceStore = com.airbridge.security.PairedDeviceStore(context)

        // Compute fingerprint of Mac's public key (raw key from QR)
        val macPubKeyBytes = android.util.Base64.decode(payload.publicKey, android.util.Base64.NO_WRAP)
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val fingerprint = digest.digest(macPubKeyBytes).joinToString("") { "%02x".format(it) }

        // Store paired device
        pairedDeviceStore.add(
            com.airbridge.security.PairedDevice(
                deviceName = "Mac",
                publicKeyBase64 = payload.publicKey,
                publicKeyFingerprint = fingerprint,
                pairedAt = System.currentTimeMillis()
            )
        )

        // Set pending pair request for when WebSocket connects
        AirbridgeService.pendingPairRequest = Triple(
            android.os.Build.MODEL,
            keyManager.getRawPublicKeyBase64(),
            payload.pairingToken
        )

        // Connect to Mac
        val intent = Intent(context, AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_CONNECT
            putExtra(AirbridgeService.EXTRA_HOST, payload.host)
            putExtra(AirbridgeService.EXTRA_PORT, payload.port)
        }
        context.startForegroundService(intent)
    }
}
