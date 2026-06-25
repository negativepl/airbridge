package com.airbridge.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import com.airbridge.protocol.ContentType
import com.airbridge.service.ActivityItem
import com.airbridge.service.AirbridgeService
import com.airbridge.stats.Stats
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
    val stats: StateFlow<Stats> = AirbridgeService.statsFlow
    val transferProgress: StateFlow<Float?> = AirbridgeService.transferProgress
    val transferFileName: StateFlow<String?> = AirbridgeService.transferFileName
    val transferSpeedBps: StateFlow<Long> = AirbridgeService.transferSpeedBps
    val transferEtaSeconds: StateFlow<Int> = AirbridgeService.transferEtaSeconds
    val transferSpeedHistory: StateFlow<List<Float>> = AirbridgeService.transferSpeedHistory

    // Mac Files Browser state
    val macFilesEntries = AirbridgeService.macFilesEntries
    val macFilesPath = AirbridgeService.macFilesPath
    val macFilesNeedsPermission = AirbridgeService.macFilesNeedsPermission
    val macFilesLoading = AirbridgeService.macFilesLoading
    val macFilesThumbnails = AirbridgeService.macFilesThumbnails
    val macFolderStats = AirbridgeService.macFolderStats

    private val _showQrScanner = MutableStateFlow(false)
    val showQrScanner: StateFlow<Boolean> = _showQrScanner.asStateFlow()

    fun startService() {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_START_DISCOVERY
        }
        getApplication<Application>().startForegroundService(intent)
    }

    /**
     * Nudge the service to re-run discovery when the app returns to the
     * foreground. The service ignores it while connected, so this is a no-op in
     * the common case and an instant recovery when a background discovery had
     * gone stale (missed network edge). Cheaper than waiting for the watchdog.
     */
    fun rediscover() {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_REDISCOVER
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

    // Mac Files Browser actions

    fun openMacFolder(
        path: String,
        sortBy: String = "name",
        sortDir: String = "asc",
        foldersFirst: Boolean = true,
        query: String = ""
    ) = AirbridgeService.requestMacFilesList(path, 0, sortBy, sortDir, foldersFirst, query)

    fun requestMacThumb(path: String) = AirbridgeService.requestMacFileThumbnail(path)

    fun requestMacStats(path: String) = AirbridgeService.requestMacFolderStats(path)

    fun downloadMacFile(path: String) = AirbridgeService.downloadMacFile(path)

    fun uploadToMac(uri: Uri, destinationDir: String) {
        val intent = Intent(getApplication(), AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_SEND_FILE
            putExtra(AirbridgeService.EXTRA_FILE_URI, uri)
            putExtra(AirbridgeService.EXTRA_DESTINATION_DIR, destinationDir)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        getApplication<Application>().startService(intent)
    }

    fun handlePairingPayload(payload: com.airbridge.pairing.PairingPayload) {
        val context = getApplication<Application>()

        // A QR with no TLS fingerprint comes from a pre-TLS Mac app. Both apps
        // ship together — refuse instead of pairing without a pin.
        if (payload.certFingerprint.isBlank()) {
            android.util.Log.e(
                "MainViewModel",
                "Pairing QR has no cert_fingerprint — Mac app is outdated, refusing to pair"
            )
            return
        }

        val keyManager = com.airbridge.security.KeyManager(context)
        val pairedDeviceStore = com.airbridge.security.PairedDeviceStore(context)

        // Compute fingerprint of Mac's public key (raw key from QR)
        val fingerprint = com.airbridge.security.KeyManager.fingerprintOf(payload.publicKey)

        // Store paired device
        pairedDeviceStore.add(
            com.airbridge.security.PairedDevice(
                deviceName = "Mac",
                publicKeyBase64 = payload.publicKey,
                publicKeyFingerprint = fingerprint,
                pairedAt = System.currentTimeMillis(),
                certFingerprint = payload.certFingerprint
            )
        )

        // Persist the mirror/pairing token so the phone can initiate screen
        // sharing (reverse mirror) on its own later.
        context.getSharedPreferences("airbridge_prefs", android.content.Context.MODE_PRIVATE)
            .edit().putString("mirror_token", payload.pairingToken).apply()

        // Set pending pair request for when WebSocket connects. The Mac's key
        // from the QR is carried along so the service can verify that the
        // PairResponse presents the same key (MITM protection during pairing).
        AirbridgeService.pendingPairRequest = AirbridgeService.PendingPairRequest(
            deviceName = android.os.Build.MODEL,
            phonePublicKeyBase64 = keyManager.getRawPublicKeyBase64(),
            pairingToken = payload.pairingToken,
            expectedMacPublicKeyBase64 = payload.publicKey,
            certFingerprint = payload.certFingerprint
        )

        // Connect to Mac
        val intent = Intent(context, AirbridgeService::class.java).apply {
            action = AirbridgeService.ACTION_CONNECT
            putExtra(AirbridgeService.EXTRA_HOST, payload.host)
            putExtra(AirbridgeService.EXTRA_PORT, payload.port)
            putExtra(AirbridgeService.EXTRA_CERT_FINGERPRINT, payload.certFingerprint)
        }
        context.startForegroundService(intent)
    }
}
