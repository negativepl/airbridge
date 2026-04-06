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

data class FileTransferState(
    val transferId: String,
    val filename: String,
    val totalSize: Long,
    val totalChunks: Int,
    val chunks: MutableMap<Int, ByteArray> = mutableMapOf()
) {
    val isComplete: Boolean get() = chunks.size == totalChunks
    val progress: Float get() = if (totalChunks == 0) 1f else chunks.size.toFloat() / totalChunks
    fun assemble(): ByteArray {
        val out = java.io.ByteArrayOutputStream(totalSize.toInt())
        for (i in 0 until totalChunks) {
            out.write(chunks[i] ?: throw IllegalStateException("Missing chunk $i"))
        }
        return out.toByteArray()
    }
}

data class ActivityItem(
    val type: String, // "clipboard_sent", "clipboard_received", "file_sent", "file_received", "ping"
    val description: String,
    val timestamp: Long
)

class AirbridgeService : Service() {

    companion object {
        private const val TAG = "AirbridgeService"

        const val CHANNEL_ID = "airbridge_service"
        const val CHANNEL_FILES_ID = "airbridge_files"
        const val NOTIFICATION_ID = 1

        const val ACTION_START_DISCOVERY = "com.airbridge.action.START_DISCOVERY"
        const val ACTION_CONNECT = "com.airbridge.action.CONNECT"
        const val ACTION_SEND_FILE = "com.airbridge.action.SEND_FILE"
        const val ACTION_DISCONNECT = "com.airbridge.action.DISCONNECT"
        const val ACTION_ACCEPT_FILE = "com.airbridge.action.ACCEPT_FILE"
        const val ACTION_REJECT_FILE = "com.airbridge.action.REJECT_FILE"

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
        val transferIsSending = MutableStateFlow(true)  // true = sending, false = receiving
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
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val httpFileUploader = HttpFileUploader()
    private val httpFileServer = HttpFileServer()
    private val activeTransfers = mutableMapOf<String, FileTransferState>()
    private lateinit var galleryProvider: GalleryProvider
    private lateinit var smsProvider: SmsProvider
    private lateinit var keyManager: com.airbridge.security.KeyManager
    private lateinit var pairedDeviceStore: com.airbridge.security.PairedDeviceStore

    override fun onCreate() {
        super.onCreate()
        instance = this

        createNotificationChannel()
        startForegroundWithNotification("Airbridge", getString(com.airbridge.R.string.notification_running_background))

        webSocketClient = WebSocketClient()
        clipboardSync = ClipboardSync(this)
        nsdDiscovery = NsdDiscovery(this)
        galleryProvider = GalleryProvider(contentResolver)
        smsProvider = SmsProvider(applicationContext)
        keyManager = com.airbridge.security.KeyManager(this)
        pairedDeviceStore = com.airbridge.security.PairedDeviceStore(this)

        setupWebSocketCallbacks()
        setupClipboardSync()
        setupNsdDiscovery()
        setupHttpFileServer()
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
                    connectedHost.value = host
                    webSocketClient.shouldReconnect = true
                    webSocketClient.connect(host, port)
                } else {
                    Log.w(TAG, "ACTION_CONNECT missing host or port")
                }
            }
            ACTION_SEND_FILE -> {
                val uri: Uri? = intent.data
                val text: String? = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (uri != null) {
                    Log.d(TAG, "File transfer requested: $uri")
                    handleSendFile(uri)
                } else if (!text.isNullOrEmpty()) {
                    Log.d(TAG, "Text share requested: '${text.take(50)}'")
                    sendClipboardToMac(ContentType.PLAIN_TEXT, text)
                }
            }
            ACTION_ACCEPT_FILE -> {
                val transferId = intent.getStringExtra("transferId")
                if (transferId != null) {
                    val offer = pendingOffers.remove(transferId)
                    val notifId = (transferId.hashCode() and 0x7FFFFFFF) % 100000 + 100
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId)
                    if (offer != null) {
                        Log.d(TAG, "File accepted: ${offer.filename}")
                        webSocketClient.send(Message.FileTransferAccept(transferId))
                    }
                }
            }
            ACTION_REJECT_FILE -> {
                val transferId = intent.getStringExtra("transferId")
                if (transferId != null) {
                    val offer = pendingOffers.remove(transferId)
                    val notifId = (transferId.hashCode() and 0x7FFFFFFF) % 100000 + 100
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.cancel(notifId)
                    if (offer != null) {
                        Log.d(TAG, "File rejected: ${offer.filename}")
                        webSocketClient.send(Message.FileTransferReject(transferId))
                        val notif = Notification.Builder(this, CHANNEL_FILES_ID)
                            .setContentTitle(getString(com.airbridge.R.string.notification_title_file_rejected))
                            .setContentText(offer.filename)
                            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                            .setContentIntent(openAppPendingIntent())
                            .setAutoCancel(true)
                            .build()
                        manager.notify(3, notif)
                    }
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
        httpFileServer.stop()
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
            nsdDiscovery.stopDiscovery()
            webSocketClient.shouldReconnect = true
            webSocketClient.connect(host, port)
        }
    }

    private val pendingOffers = mutableMapOf<String, Message.FileTransferOffer>() // transferId -> offer
    private val pendingOutgoingOffers = mutableMapOf<String, kotlinx.coroutines.CompletableDeferred<Boolean>>()
    private var lastProgressNotifUpdate = 0L

    private fun setupHttpFileServer() {
        httpFileServer.onProgress = { filename, bytesReceived, totalBytes ->
            transferFileName.value = filename
            transferIsSending.value = false
            val progress = bytesReceived.toFloat() / totalBytes
            transferProgress.value = progress

            // Throttle notification updates to max every 300ms
            val now = System.currentTimeMillis()
            if (now - lastProgressNotifUpdate >= 300 || bytesReceived >= totalBytes) {
                lastProgressNotifUpdate = now
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val sender = connectedDeviceName.value ?: "Mac"
                val sizeText = when {
                    totalBytes > 1024 * 1024 -> String.format("%.1f MB", totalBytes / (1024.0 * 1024.0))
                    totalBytes > 1024 -> String.format("%.0f KB", totalBytes / 1024.0)
                    else -> "$totalBytes B"
                }
                val progressPercent = (progress * 100).toInt()
                val notifBuilder = Notification.Builder(this, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_receiving, sender))
                    .setContentText("$filename · $sizeText · $progressPercent%")
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setContentIntent(openAppPendingIntent())
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
                    val accentColor = android.graphics.Color.parseColor("#4285F4")
                    val grayColor = android.graphics.Color.parseColor("#444444")
                    notifBuilder.style = Notification.ProgressStyle().apply {
                        this.progress = progressPercent
                        this.progressSegments = listOf(
                            Notification.ProgressStyle.Segment(progressPercent).setColor(accentColor),
                            Notification.ProgressStyle.Segment(100 - progressPercent).setColor(grayColor)
                        )
                    }
                }
                manager.notify(4, notifBuilder.build())
            }
        }
        httpFileServer.onFileReceived = { filename, _, tempFile ->
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(4)
            serviceScope.launch {
                try {
                    val prefs = getSharedPreferences("airbridge_prefs", MODE_PRIVATE)
                    val folder = prefs.getString("download_folder", null)
                        ?: android.os.Environment.getExternalStoragePublicDirectory(
                            android.os.Environment.DIRECTORY_DOWNLOADS
                        ).absolutePath + "/Airbridge"
                    val dir = java.io.File(folder)
                    if (!dir.exists()) dir.mkdirs()
                    val file = java.io.File(dir, filename)
                    tempFile.copyTo(file, overwrite = true)
                    tempFile.delete()
                    Log.d(TAG, "File received: ${file.absolutePath}")
                    addActivity(ActivityItem("file_received", filename, System.currentTimeMillis()))
                    transferProgress.value = null
                    transferFileName.value = null

                    val notif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                        .setContentTitle(getString(com.airbridge.R.string.notification_title_file_received))
                        .setContentText(filename)
                        .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                        .setContentIntent(openAppPendingIntent())
                        .setAutoCancel(true)
                        .build()
                    manager.notify(3, notif)
                } catch (e: Exception) {
                    Log.e(TAG, "File save failed", e)
                    transferProgress.value = null
                    transferFileName.value = null
                }
            }
        }
        httpFileServer.start()

    }

    private fun handleFileTransferOffer(offer: Message.FileTransferOffer) {
        pendingOffers[offer.transferId] = offer
        val sender = connectedDeviceName.value ?: "Mac"
        val sizeText = when {
            offer.fileSize > 1024 * 1024 -> String.format("%.1f MB", offer.fileSize / (1024.0 * 1024.0))
            offer.fileSize > 1024 -> String.format("%.0f KB", offer.fileSize / 1024.0)
            else -> "${offer.fileSize} B"
        }
        val notifId = (offer.transferId.hashCode() and 0x7FFFFFFF) % 100000 + 100
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val acceptIntent = android.app.PendingIntent.getService(
            this, notifId,
            Intent(this, AirbridgeService::class.java).apply {
                action = ACTION_ACCEPT_FILE
                putExtra("transferId", offer.transferId)
            },
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        val rejectIntent = android.app.PendingIntent.getService(
            this, notifId + 50000,
            Intent(this, AirbridgeService::class.java).apply {
                action = ACTION_REJECT_FILE
                putExtra("transferId", offer.transferId)
            },
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notif = Notification.Builder(this, CHANNEL_FILES_ID)
            .setContentTitle(getString(com.airbridge.R.string.notification_accept_file, sender))
            .setContentText(getString(com.airbridge.R.string.notification_accept_file_detail, offer.filename, sizeText))
            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
            .setContentIntent(openAppPendingIntent())
            .addAction(Notification.Action.Builder(null, getString(com.airbridge.R.string.notification_reject), rejectIntent).build())
            .addAction(Notification.Action.Builder(null, getString(com.airbridge.R.string.notification_accept), acceptIntent).build())
            .setAutoCancel(false)
            .setOngoing(true)
            .build()
        manager.notify(notifId, notif)
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
            is Message.FileTransferOffer -> {
                handleFileTransferOffer(message)
            }
            is Message.FileTransferAccept -> {
                pendingOutgoingOffers.remove(message.transferId)?.complete(true)
            }
            is Message.FileTransferReject -> {
                pendingOutgoingOffers.remove(message.transferId)?.complete(false)
            }
            is Message.FileTransferStart -> {
                Log.d(TAG, "FileTransferStart: ${message.filename} (${message.totalChunks} chunks)")
                activeTransfers[message.transferId] = FileTransferState(
                    transferId = message.transferId,
                    filename = message.filename,
                    totalSize = message.totalSize,
                    totalChunks = message.totalChunks
                )
                transferFileName.value = message.filename
                transferIsSending.value = false
                transferProgress.value = 0f

                // Show receiving notification with file info
                val sizeText = when {
                    message.totalSize > 1024 * 1024 -> String.format("%.1f MB", message.totalSize / (1024.0 * 1024.0))
                    message.totalSize > 1024 -> String.format("%.0f KB", message.totalSize / 1024.0)
                    else -> "${message.totalSize} B"
                }
                val sender = connectedDeviceName.value ?: "Mac"
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val notif = Notification.Builder(this, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_receiving, sender))
                    .setContentText("${message.filename} · $sizeText")
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setContentIntent(openAppPendingIntent())
                    .setProgress(100, 0, false)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .build()
                manager.notify(4, notif)
            }
            is Message.FileChunk -> {
                val transfer = activeTransfers[message.transferId] ?: return
                val chunkData = android.util.Base64.decode(message.data, android.util.Base64.NO_WRAP)
                transfer.chunks[message.chunkIndex] = chunkData
                transferProgress.value = transfer.progress
                webSocketClient.send(Message.FileChunkAck(message.transferId, message.chunkIndex))

                // Update progress notification
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val progress = (transfer.progress * 100).toInt()
                val sender = connectedDeviceName.value ?: "Mac"
                val notif = Notification.Builder(this, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_receiving, sender))
                    .setContentText(transfer.filename)
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setContentIntent(openAppPendingIntent())
                    .setProgress(100, progress, false)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .build()
                manager.notify(4, notif)
            }
            is Message.FileTransferComplete -> {
                val transfer = activeTransfers.remove(message.transferId) ?: return
                serviceScope.launch {
                    try {
                        val data = transfer.assemble()
                        val prefs = getSharedPreferences("airbridge_prefs", MODE_PRIVATE)
                        val folder = prefs.getString("download_folder", null)
                            ?: android.os.Environment.getExternalStoragePublicDirectory(
                                android.os.Environment.DIRECTORY_DOWNLOADS
                            ).absolutePath + "/Airbridge"
                        val dir = java.io.File(folder)
                        if (!dir.exists()) dir.mkdirs()
                        val file = java.io.File(dir, transfer.filename)
                        file.writeBytes(data)
                        Log.d(TAG, "File received: ${file.absolutePath}")
                        addActivity(ActivityItem("file_received", transfer.filename, System.currentTimeMillis()))
                        transferProgress.value = null
                        transferFileName.value = null

                        // Cancel progress notification, show completion
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        manager.cancel(4)
                        val notif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                            .setContentTitle(getString(com.airbridge.R.string.notification_title_file_received))
                            .setContentText(transfer.filename)
                            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                            .setContentIntent(openAppPendingIntent())
                            .setAutoCancel(true)
                            .build()
                        manager.notify(3, notif)
                    } catch (e: Exception) {
                        Log.e(TAG, "File save failed", e)
                        transferProgress.value = null
                        transferFileName.value = null
                    }
                }
            }
            is Message.FileChunkAck -> {
                // ACK from Android → Mac transfers
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
            android.widget.Toast.makeText(this, getString(com.airbridge.R.string.not_connected), android.widget.Toast.LENGTH_SHORT).show()
            return
        }

        val host = connectedHost.value ?: run {
            Log.w(TAG, "handleSendFile: no host")
            android.widget.Toast.makeText(this, getString(com.airbridge.R.string.not_connected), android.widget.Toast.LENGTH_SHORT).show()
            return
        }
        val port = httpPort.value

        // Resolve filename + size for UI
        var filename = "file"
        var fileSize = 0L
        applicationContext.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIdx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (nameIdx >= 0) cursor.getString(nameIdx)?.let { filename = it }
                val sizeIdx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                if (sizeIdx >= 0) fileSize = cursor.getLong(sizeIdx)
            }
        }

        transferFileName.value = filename
        transferIsSending.value = true
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
        val targetName = connectedDeviceName.value ?: "Mac"
        fun updateTransferNotification(progress: Int, speed: String) {
            val notifBuilder = Notification.Builder(this, CHANNEL_FILES_ID)
                .setContentTitle(getString(com.airbridge.R.string.notification_title_sending, targetName))
                .setContentText(if (speed.isNotEmpty()) "$filename · $speed" else filename)
                .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openIntent)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
                val accentColor = android.graphics.Color.parseColor("#4285F4")
                val grayColor = android.graphics.Color.parseColor("#444444")
                notifBuilder.style = Notification.ProgressStyle().apply {
                    this.progress = progress
                    this.progressSegments = listOf(
                        Notification.ProgressStyle.Segment(maxOf(progress, 1)).setColor(accentColor),
                        Notification.ProgressStyle.Segment(maxOf(100 - progress, 1)).setColor(grayColor)
                    )
                }
            }
            manager.notify(transferNotifId, notifBuilder.build())
        }
        updateTransferNotification(0, "")

        serviceScope.launch {
            // 1. Send offer and wait for accept/reject
            val transferId = java.util.UUID.randomUUID().toString()
            val deferred = kotlinx.coroutines.CompletableDeferred<Boolean>()
            pendingOutgoingOffers[transferId] = deferred
            val mime = applicationContext.contentResolver.getType(uri) ?: "application/octet-stream"
            webSocketClient.send(Message.FileTransferOffer(transferId, filename, mime, fileSize))

            val accepted = try {
                kotlinx.coroutines.withTimeoutOrNull(60_000) { deferred.await() } ?: false
            } catch (_: Exception) { false }

            if (!accepted) {
                pendingOutgoingOffers.remove(transferId)
                Log.d(TAG, "Offer rejected or timed out for $filename")
                transferIsSending.value = false
                transferProgress.value = null
                transferFileName.value = null
                val rejNotif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_file_rejected))
                    .setContentText(filename)
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setContentIntent(openAppPendingIntent())
                    .setAutoCancel(true)
                    .build()
                manager.notify(transferNotifId, rejNotif)
                return@launch
            }

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
                val doneNotif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_file_sent))
                    .setContentText(filename)
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setOngoing(false)
                    .setContentIntent(openIntent)
                    .setAutoCancel(true)
                    .build()
                manager.notify(transferNotifId, doneNotif)
            } else {
                Log.e(TAG, "HTTP transfer failed: $filename")
                val failNotif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_file_error))
                    .setContentText(filename)
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
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val serviceChannel = NotificationChannel(
            CHANNEL_ID,
            getString(com.airbridge.R.string.channel_service_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(com.airbridge.R.string.channel_service_desc)
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        val fileChannel = NotificationChannel(
            CHANNEL_FILES_ID,
            getString(com.airbridge.R.string.channel_files_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(com.airbridge.R.string.channel_files_desc)
        }
        manager.createNotificationChannel(serviceChannel)
        manager.createNotificationChannel(fileChannel)
    }

    private fun openAppPendingIntent(): android.app.PendingIntent =
        android.app.PendingIntent.getActivity(
            this, 0,
            android.content.Intent(this, com.airbridge.ui.MainActivity::class.java).apply {
                flags = android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            android.app.PendingIntent.FLAG_IMMUTABLE
        )

    private fun buildNotification(title: String, text: String): Notification =
        Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(openAppPendingIntent())
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

}
