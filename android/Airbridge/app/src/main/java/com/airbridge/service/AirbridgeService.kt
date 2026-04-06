package com.airbridge.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.airbridge.clipboard.ClipboardSync
import com.airbridge.discovery.NsdDiscovery
import com.airbridge.gallery.GalleryProvider
import com.airbridge.protocol.ContentType
import com.airbridge.protocol.Message
import com.airbridge.sms.SmsProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

data class ActivityItem(
    val type: String, // "clipboard_sent", "clipboard_received", "file_sent", "file_received", "ping"
    val description: String,
    val timestamp: Long
)

class AirbridgeService : Service() {

    companion object {
        private const val TAG = "AirbridgeService"

        const val CHANNEL_ID = "airbridge_service"
        const val NOTIFICATION_ID = 1

        const val ACTION_START_DISCOVERY = "com.airbridge.action.START_DISCOVERY"
        const val ACTION_CONNECT = "com.airbridge.action.CONNECT"
        const val ACTION_SEND_FILE = "com.airbridge.action.SEND_FILE"
        const val ACTION_DISCONNECT = "com.airbridge.action.DISCONNECT"

        const val EXTRA_HOST = "extra_host"
        const val EXTRA_PORT = "extra_port"

        // Shared state observable by UI
        val isConnected = MutableStateFlow(false)
        val connectedDeviceName = MutableStateFlow<String?>(null)
        val connectedHost = MutableStateFlow<String?>(null)
        val connectedSince = MutableStateFlow<Long?>(null)
        val recentActivity = MutableStateFlow<List<ActivityItem>>(emptyList())

        // Transfer progress: null = no transfer, 0.0..1.0 = in progress
        val transferProgress = MutableStateFlow<Float?>(null)
        val transferFileName = MutableStateFlow<String?>(null)
        val httpPort = MutableStateFlow(8766)
        val transferSpeedBps = MutableStateFlow<Long>(0)  // bytes per second
        val transferEtaSeconds = MutableStateFlow<Int>(0)
        val transferSpeedHistory = MutableStateFlow<List<Float>>(emptyList())  // normalized 0-1 speed samples

        fun addActivity(item: ActivityItem) {
            recentActivity.value = (listOf(item) + recentActivity.value).take(10)
        }

        // Reference to running instance for AccessibilityService to send clipboard
        @Volatile
        private var instance: AirbridgeService? = null

        fun sendClipboardToMac(contentType: ContentType, data: String) {
            val svc = instance ?: run {
                Log.w(TAG, "sendClipboardToMac: service not running")
                return
            }
            if (!svc.webSocketClient.isConnected) return
            val msg = Message.ClipboardUpdate(
                sourceId = svc.deviceId,
                contentType = contentType,
                data = data
            )
            svc.webSocketClient.send(msg)
            addActivity(ActivityItem("clipboard_sent", "", System.currentTimeMillis()))
            Log.d(TAG, "Sent clipboard to Mac: '${data.take(50)}'")
        }

        fun sendPing() {
            instance?.sendPing()
        }

        @Volatile
        var pendingPairRequest: Triple<String, String, String>? = null  // (deviceName, publicKey, token)
    }

    private val deviceId: String = UUID.randomUUID().toString()

    private lateinit var webSocketClient: WebSocketClient
    private lateinit var clipboardSync: ClipboardSync
    private lateinit var nsdDiscovery: NsdDiscovery
    private var localDeviceName: String? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val httpFileUploader = HttpFileUploader()
    private lateinit var galleryProvider: GalleryProvider
    private lateinit var smsProvider: SmsProvider
    private lateinit var keyManager: com.airbridge.security.KeyManager
    private lateinit var pairedDeviceStore: com.airbridge.security.PairedDeviceStore

    override fun onCreate() {
        super.onCreate()
        instance = this

        createNotificationChannel()
        startForegroundWithNotification("Airbridge", "Działa w tle")

        webSocketClient = WebSocketClient()
        clipboardSync = ClipboardSync(this)
        nsdDiscovery = NsdDiscovery(this)
        galleryProvider = GalleryProvider(contentResolver)
        smsProvider = SmsProvider(contentResolver)
        keyManager = com.airbridge.security.KeyManager(this)
        pairedDeviceStore = com.airbridge.security.PairedDeviceStore(this)

        setupWebSocketCallbacks()
        setupClipboardSync()
        setupNsdDiscovery()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_DISCOVERY -> {
                Log.d(TAG, "Starting NSD discovery")
                nsdDiscovery.startDiscovery()
            }
            ACTION_CONNECT -> {
                val host = intent.getStringExtra(EXTRA_HOST)
                val port = intent.getIntExtra(EXTRA_PORT, 0)
                if (host != null && port != 0) {
                    Log.d(TAG, "Connecting directly to $host:$port")
                    webSocketClient.shouldReconnect = true
                    webSocketClient.connect(host, port)
                } else {
                    Log.w(TAG, "ACTION_CONNECT missing host or port")
                }
            }
            ACTION_SEND_FILE -> {
                val uri: Uri? = intent.data
                if (uri != null) {
                    Log.d(TAG, "File transfer requested: $uri")
                    handleSendFile(uri)
                }
            }
            ACTION_DISCONNECT -> {
                Log.d(TAG, "Disconnecting and stopping service")
                nsdDiscovery.stopDiscovery()
                webSocketClient.disconnect()
                isConnected.value = false
                connectedDeviceName.value = null
                connectedSince.value = null
                connectedHost.value = null
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        clipboardSync.stopListening()
        nsdDiscovery.stopDiscovery()
        webSocketClient.disconnect()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --- Setup ---

    private fun setupWebSocketCallbacks() {
        webSocketClient.onConnected = {
            Log.d(TAG, "WebSocket connected — sending auth or pair request")
            val pending = pendingPairRequest
            if (pending != null) {
                pendingPairRequest = null
                sendPairRequest(pending.first, pending.second, pending.third)
            } else {
                // Normal reconnect — send auth handshake
                val timestamp = System.currentTimeMillis()
                val timestampBytes = timestamp.toString().toByteArray(Charsets.UTF_8)
                val signature = keyManager.sign(timestampBytes)
                val publicKey = keyManager.getRawPublicKeyBase64()
                val authMsg = Message.AuthRequest(
                    publicKey = publicKey,
                    signature = signature,
                    timestamp = timestamp
                )
                webSocketClient.send(authMsg)
            }
        }

        webSocketClient.onDisconnected = {
            Log.d(TAG, "WebSocket disconnected")
            clipboardSync.stopListening()
            isConnected.value = false
            connectedSince.value = null
            // Keep connectedHost — WebSocket auto-reconnects to same host
            // status tracked via StateFlow, no notification update needed
        }

        webSocketClient.onMessage = { message ->
            handleIncomingMessage(message)
        }
    }

    private var lastRemoteClipHash: String? = null

    private fun setupClipboardSync() {
        // Clipboard sync is handled via:
        // - Mac → Phone: WebSocket message → clipboardSync.setClipboard()
        // - Phone → Mac: "Send to Mac" text selection menu (SendToMacActivity)
        //                + "Send clipboard" button in UI (AirbridgeService.sendClipboardToMac)
    }

    private fun sha256(input: String): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun setupNsdDiscovery() {
        nsdDiscovery.onServiceFound = handler@{ host, port, deviceName, httpPort, fingerprint ->
            if (fingerprint.isEmpty()) {
                Log.d(TAG, "NSD: $deviceName has no fingerprint — skipping")
                return@handler
            }
            if (!pairedDeviceStore.isPaired(fingerprint)) {
                Log.d(TAG, "NSD: $deviceName not paired (fp=${fingerprint.take(16)}...) — skipping")
                return@handler
            }
            Log.d(TAG, "NSD: paired device $deviceName found at $host:$port — connecting")
            connectedHost.value = host
            connectedDeviceName.value = deviceName
            Companion.httpPort.value = httpPort
            localDeviceName = deviceName
            nsdDiscovery.stopDiscovery()
            webSocketClient.shouldReconnect = true
            webSocketClient.connect(host, port)
        }
    }

    // --- Message handling ---

    private fun handleIncomingMessage(message: Message) {
        when (message) {
            is Message.ClipboardUpdate -> {
                if (message.sourceId == deviceId) {
                    Log.d(TAG, "Ignoring own clipboard update")
                    return
                }
                Log.d(TAG, "Received clipboard: type=${message.contentType.value} data='${message.data.take(50)}'")
                if (message.contentType == ContentType.PLAIN_TEXT || message.contentType == ContentType.HTML) {
                    val hash = sha256(message.data)
                    lastRemoteClipHash = hash
                    clipboardSync.setClipboard(message.data)
                    addActivity(ActivityItem("clipboard_received", "", System.currentTimeMillis()))
                    Log.d(TAG, "Applied remote clipboard update")
                }
            }
            is Message.AuthResponse -> {
                if (message.accepted) {
                    Log.d(TAG, "Auth accepted — connection authenticated")
                    clipboardSync.startListening()
                    isConnected.value = true
                    connectedSince.value = System.currentTimeMillis()
                    val name = localDeviceName ?: "device"
                    // connection status tracked via StateFlow
                } else {
                    Log.w(TAG, "Auth rejected: ${message.reason}")
                    webSocketClient.shouldReconnect = false
                    webSocketClient.disconnect()
                    isConnected.value = false
                    // auth failure tracked via StateFlow
                }
            }
            is Message.PairResponse -> {
                localDeviceName = message.deviceName
                connectedDeviceName.value = message.deviceName
                if (message.accepted) {
                    // Update stored device name with Mac's actual name
                    val macPubKeyBytes = android.util.Base64.decode(message.publicKey, android.util.Base64.NO_WRAP)
                    val digest = java.security.MessageDigest.getInstance("SHA-256")
                    val fp = digest.digest(macPubKeyBytes).joinToString("") { "%02x".format(it) }
                    pairedDeviceStore.add(
                        com.airbridge.security.PairedDevice(
                            deviceName = message.deviceName,
                            publicKeyBase64 = message.publicKey,
                            publicKeyFingerprint = fp,
                            pairedAt = System.currentTimeMillis()
                        )
                    )
                    clipboardSync.startListening()
                    isConnected.value = true
                    connectedSince.value = System.currentTimeMillis()
                    // pairing status tracked via StateFlow
                } else {
                    isConnected.value = false
                    // pair rejection tracked via StateFlow
                }
                Log.d(TAG, "PairResponse from ${message.deviceName}: accepted=${message.accepted}")
            }
            is Message.FileChunkAck -> {
                // Legacy ACK handling — no longer used with HTTP file transfer
            }
            is Message.Pong -> {
                addActivity(ActivityItem("ping", "Pong!", System.currentTimeMillis()))
                Log.d(TAG, "Received pong")
            }
            is Message.GalleryRequest -> {
                Log.d(TAG, "GalleryRequest received: page=${message.page} pageSize=${message.pageSize}")
                serviceScope.launch {
                    try {
                        val (photos, totalCount) = galleryProvider.getPhotos(message.page, message.pageSize)
                        Log.d(TAG, "GalleryRequest: got ${photos.size} photos, total=$totalCount")
                        val response = Message.GalleryResponse(photos, totalCount, message.page)
                        webSocketClient.send(response)
                        Log.d(TAG, "GalleryResponse sent")
                    } catch (e: Exception) {
                        Log.e(TAG, "GalleryRequest failed", e)
                    }
                }
            }
            is Message.GalleryThumbnailRequest -> {
                serviceScope.launch {
                    val data = galleryProvider.getThumbnail(message.photoId)
                    if (data != null) {
                        val response = Message.GalleryThumbnailResponse(message.photoId, data)
                        webSocketClient.send(response)
                    }
                }
            }
            is Message.GalleryDownloadRequest -> {
                serviceScope.launch {
                    val uri = galleryProvider.getPhotoUri(message.photoId)
                    if (uri != null) {
                        val host = connectedHost.value
                        val port = httpPort.value
                        if (host != null) {
                            httpFileUploader.upload(
                                host = host,
                                port = port,
                                uri = uri,
                                contentResolver = applicationContext.contentResolver
                            ) { _, _ -> }
                        }
                    }
                }
            }
            is Message.SmsConversationsRequest -> {
                serviceScope.launch {
                    try {
                        val (conversations, totalCount) = smsProvider.getConversations(message.page, message.pageSize)
                        val response = Message.SmsConversationsResponse(conversations, totalCount, message.page)
                        webSocketClient.send(response)
                    } catch (e: Exception) {
                        Log.e(TAG, "SmsConversationsRequest failed", e)
                    }
                }
            }
            is Message.SmsMessagesRequest -> {
                serviceScope.launch {
                    try {
                        val (messages, totalCount) = smsProvider.getMessages(message.threadId, message.page, message.pageSize)
                        val response = Message.SmsMessagesResponse(message.threadId, messages, totalCount, message.page)
                        webSocketClient.send(response)
                    } catch (e: Exception) {
                        Log.e(TAG, "SmsMessagesRequest failed", e)
                    }
                }
            }
            is Message.SmsSendRequest -> {
                serviceScope.launch {
                    try {
                        val (success, error) = smsProvider.sendSms(message.address, message.body)
                        val response = Message.SmsSendResponse(success, error)
                        webSocketClient.send(response)
                    } catch (e: Exception) {
                        Log.e(TAG, "SmsSendRequest failed", e)
                        webSocketClient.send(Message.SmsSendResponse(false, e.message))
                    }
                }
            }
            else -> {
                Log.d(TAG, "Unhandled message type: ${message::class.simpleName}")
            }
        }
    }

    private fun handleSendFile(uri: Uri) {
        if (!webSocketClient.isConnected) {
            Log.w(TAG, "handleSendFile: not connected")
            return
        }

        val host = connectedHost.value ?: run {
            Log.w(TAG, "handleSendFile: no host")
            return
        }
        val port = httpPort.value

        // Resolve filename for UI
        val filename = applicationContext.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else null
        } ?: "file"

        transferFileName.value = filename
        transferProgress.value = 0f
        transferSpeedBps.value = 0
        transferEtaSeconds.value = 0
        transferSpeedHistory.value = emptyList()

        // Show transfer notification with tap-to-open
        val transferNotifId = 2
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openIntent = android.app.PendingIntent.getActivity(
            this, 0,
            android.content.Intent(this, com.airbridge.ui.MainActivity::class.java).apply {
                flags = android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            android.app.PendingIntent.FLAG_IMMUTABLE
        )
        fun updateTransferNotification(progress: Int, speed: String) {
            val notif = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Airbridge — $filename")
                .setContentText(if (speed.isNotEmpty()) speed else "Wysyłanie…")
                .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                .setProgress(100, progress, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openIntent)
                .build()
            manager.notify(transferNotifId, notif)
        }
        updateTransferNotification(0, "")

        serviceScope.launch {
            val startTime = System.currentTimeMillis()
            var lastFileSize = 0L
            var peakSpeed = 1L
            var lastSampleTime = 0L
            var lastNotifUpdate = 0L

            val success = httpFileUploader.upload(
                host = host,
                port = port,
                uri = uri,
                contentResolver = applicationContext.contentResolver
            ) { bytesSent, totalBytes ->
                lastFileSize = totalBytes
                val elapsed = System.currentTimeMillis() - startTime
                val progress = bytesSent.toFloat() / totalBytes
                transferProgress.value = progress
                if (elapsed > 0) {
                    val speed = bytesSent * 1000 / elapsed
                    transferSpeedBps.value = speed
                    if (speed > peakSpeed) peakSpeed = speed
                    val remaining = totalBytes - bytesSent
                    transferEtaSeconds.value = if (speed > 0) (remaining / speed).toInt() else 0

                    // Sample speed every 200ms for chart
                    val now = System.currentTimeMillis()
                    if (now - lastSampleTime >= 200) {
                        lastSampleTime = now
                        val normalized = (speed.toFloat() / peakSpeed).coerceIn(0f, 1f)
                        val history = transferSpeedHistory.value.toMutableList()
                        history.add(normalized)
                        if (history.size > 60) history.removeAt(0)
                        transferSpeedHistory.value = history
                    }

                    // Update notification every 500ms
                    if (now - lastNotifUpdate >= 500) {
                        lastNotifUpdate = now
                        val speedText = when {
                            speed > 1024 * 1024 -> String.format("%.1f MB/s", speed / (1024.0 * 1024.0))
                            speed > 1024 -> String.format("%.0f KB/s", speed / 1024.0)
                            else -> ""
                        }
                        updateTransferNotification((progress * 100).toInt(), speedText)
                    }
                }
            }

            val elapsed = System.currentTimeMillis() - startTime
            if (success) {
                val speedMBs = if (elapsed > 0) lastFileSize / 1024.0 / 1024.0 / (elapsed / 1000.0) else 0.0
                Log.d(TAG, "HTTP transfer complete: $filename in ${elapsed}ms (%.2f MB/s)".format(speedMBs))
                addActivity(ActivityItem("file_sent", filename, System.currentTimeMillis()))
                // Complete notification
                val doneNotif = Notification.Builder(this@AirbridgeService, CHANNEL_ID)
                    .setContentTitle("Airbridge")
                    .setContentText("$filename — wysłano")
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setOngoing(false)
                    .setContentIntent(openIntent)
                    .setAutoCancel(true)
                    .build()
                manager.notify(transferNotifId, doneNotif)
            } else {
                Log.e(TAG, "HTTP transfer failed: $filename")
                val failNotif = Notification.Builder(this@AirbridgeService, CHANNEL_ID)
                    .setContentTitle("Airbridge")
                    .setContentText("$filename — błąd wysyłania")
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setOngoing(false)
                    .setContentIntent(openIntent)
                    .setAutoCancel(true)
                    .build()
                manager.notify(transferNotifId, failNotif)
            }

            transferProgress.value = null
            transferFileName.value = null
            transferSpeedBps.value = 0
            transferEtaSeconds.value = 0
        }
    }

    // --- Ping ---

    fun sendPing() {
        if (webSocketClient.isConnected) {
            val msg = Message.Ping()
            webSocketClient.send(msg)
            addActivity(ActivityItem("ping", "Ping", System.currentTimeMillis()))
            Log.d(TAG, "Sent ping")
        }
    }

    // --- Pairing ---

    fun sendPairRequest(deviceName: String, publicKey: String, pairingToken: String) {
        val msg = Message.PairRequest(
            deviceName = deviceName,
            publicKey = publicKey,
            pairingToken = pairingToken
        )
        webSocketClient.send(msg)
        Log.d(TAG, "Sent PairRequest as $deviceName")
    }

    // --- Notification helpers ---

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Airbridge Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Airbridge background service"
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
            .setOngoing(true)
            .build()

    private fun startForegroundWithNotification(title: String, text: String) {
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(title: String, text: String) {
        val notification = buildNotification(title, text)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }
}
