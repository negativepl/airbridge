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
import com.airbridge.files.FilesProvider
import com.airbridge.network.NetworkMonitor
import com.airbridge.gallery.GalleryProvider
import com.airbridge.protocol.ContentType
import com.airbridge.protocol.Message
import com.airbridge.sms.SmsProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

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
        const val ACTION_STOP_RING = "com.airbridge.action.STOP_RING"
        private const val RING_NOTIFICATION_ID = 7

        const val EXTRA_HOST = "extra_host"
        const val EXTRA_PORT = "extra_port"
        const val EXTRA_CERT_FINGERPRINT = "extra_cert_fingerprint"

        const val ACTION_REDISCOVER = "com.airbridge.action.REDISCOVER"

        // Rediscovery watchdog cadence. With intervalTicks=2 the phone forces a
        // fresh discovery ~30s after the connection drops and every ~30s while
        // it stays down — the level-triggered backstop for a missed network
        // edge. Long enough to let WebSocketClient's own fast reconnect (~14s)
        // and onReconnectExhausted run first, so the two don't fight.
        private const val REDISCOVERY_TICK_MS = 15_000L

        // Shared state observable by UI
        val isConnected = MutableStateFlow(false)
        val connectedDeviceName = MutableStateFlow<String?>(null)
        val connectedHost = MutableStateFlow<String?>(null)
        val mirrorPortFlow = MutableStateFlow<Int?>(null)   // Mac mirror server port (phone-initiated reverse mirror)
        val macInfo = MutableStateFlow<com.airbridge.protocol.MacInfo?>(null)
        val macWallpaper = MutableStateFlow<String?>(null)  // base64 JPEG
        val connectedSince = MutableStateFlow<Long?>(null)
        val recentActivity = MutableStateFlow<List<ActivityItem>>(emptyList())

        /**
         * Visible re-pair guidance (null = no issue). Set when a paired Mac is
         * found but cannot be trusted over TLS (no stored pin, or the
         * advertised certificate differs from the pinned one); cleared on a
         * successful connect or successful pairing. Rendered in MainScreen.
         */
        val pairingIssue = MutableStateFlow<String?>(null)

        // Transfer progress: null = no transfer, 0.0..1.0 = in progress
        val transferProgress = MutableStateFlow<Float?>(null)
        val transferFileName = MutableStateFlow<String?>(null)
        val transferIsSending = MutableStateFlow(true)  // true = sending, false = receiving
        val httpPort = MutableStateFlow(8766)
        val transferSpeedBps = MutableStateFlow<Long>(0)  // bytes per second
        val transferEtaSeconds = MutableStateFlow<Int>(0)
        val transferSpeedHistory = MutableStateFlow<List<Float>>(emptyList())  // normalized 0-1 speed samples

        fun addActivity(item: ActivityItem) {
            // Atomic read-modify-write: callers run on arbitrary threads
            // (WebSocket callbacks, IO coroutines, main thread).
            recentActivity.update { (listOf(item) + it).take(10) }
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
            Log.d(TAG, "Sent clipboard to Mac (${data.length} chars)")
        }

        fun sendPing() {
            instance?.sendPing()
        }

        /** Re-request the Mac's live system info (for the Home monitor refresh). */
        fun requestMacInfo() {
            val svc = instance ?: return
            if (svc.webSocketClient.isConnected) svc.webSocketClient.send(Message.MacInfoRequest)
        }

        /** Most z NotificationRelayService: wyślij powiadomienie na Maca, gdy połączony. */
        fun relayNotification(
            packageName: String, appName: String, title: String, text: String,
            timestamp: Long, appIcon: String, notificationKey: String = "", canReply: Boolean = false
        ) {
            val svc = instance ?: return
            if (!svc.webSocketClient.isConnected) return
            svc.webSocketClient.send(
                Message.NotificationPosted(packageName, appName, title, text, timestamp, appIcon, notificationKey, canReply)
            )
        }

        @Volatile
        var pendingPairRequest: PendingPairRequest? = null

        /** TLS pin of the live connection — for external call sites (UI/
         *  Activities, e.g. screen share) that launch their own pinned clients
         *  to the same Mac; code inside the service reads
         *  `webSocketClient.certFingerprintInUse` directly. */
        fun certFingerprintInUse(): String =
            instance?.webSocketClient?.certFingerprintInUse ?: ""
    }

    /** Pairing data captured from a scanned QR code, consumed once the WebSocket connects. */
    data class PendingPairRequest(
        val deviceName: String,
        val phonePublicKeyBase64: String,
        val pairingToken: String,
        /** The Mac's public key as scanned from the QR code — trust anchor for PairResponse. */
        val expectedMacPublicKeyBase64: String,
        /** SHA-256 hex of the Mac's TLS certificate DER, from the same QR. */
        val certFingerprint: String
    )

    private val deviceId: String = UUID.randomUUID().toString()

    private lateinit var webSocketClient: WebSocketClient
    private lateinit var clipboardSync: ClipboardSync
    private lateinit var nsdDiscovery: NsdDiscovery
    private lateinit var networkMonitor: NetworkMonitor
    private val rediscoveryWatchdog = RediscoveryWatchdog()
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val httpFileUploader = HttpFileUploader()
    private val httpFileDownloader = HttpFileDownloader()
    private val httpFileServer = HttpFileServer()
    private lateinit var galleryProvider: GalleryProvider
    private val filesProvider by lazy { FilesProvider(contentResolver) }
    private lateinit var smsProvider: SmsProvider
    private lateinit var keyManager: com.airbridge.security.KeyManager
    private lateinit var pairedDeviceStore: com.airbridge.security.PairedDeviceStore
    private var currentMirrorPort: Int? = null

    /**
     * The Mac's public key from the scanned QR code, set when a PairRequest is
     * sent and verified against the key carried by the PairResponse. A mismatch
     * means an active MITM substituted its own key during pairing.
     */
    @Volatile
    private var expectedMacPublicKey: String? = null

    /**
     * The Mac's TLS cert fingerprint from the scanned QR code, held between
     * sending the PairRequest and the accepted PairResponse so the stored
     * PairedDevice can carry the pin. Lifecycle mirrors [expectedMacPublicKey].
     */
    @Volatile
    private var pendingPairCertFingerprint: String? = null

    override fun onCreate() {
        super.onCreate()
        instance = this

        createNotificationChannel()
        startForegroundWithNotification("AirBridge", getString(com.airbridge.R.string.notification_running_background))

        webSocketClient = WebSocketClient()
        clipboardSync = ClipboardSync(this)
        nsdDiscovery = NsdDiscovery(this)
        networkMonitor = NetworkMonitor(this) { onNetworkChanged() }
        galleryProvider = GalleryProvider(contentResolver)
        smsProvider = SmsProvider(applicationContext)
        keyManager = com.airbridge.security.KeyManager(this)
        pairedDeviceStore = com.airbridge.security.PairedDeviceStore(this)

        setupWebSocketCallbacks()
        setupClipboardSync()
        setupNsdDiscovery()
        setupHttpFileServer()
        networkMonitor.start()
        startRediscoveryWatchdog()
    }

    /**
     * Level-triggered backstop: while the service runs but the connection is
     * down, periodically force a fresh discovery. Edge-triggered restarts (on a
     * network change) can be missed or silently fail — multicast throttled in
     * Doze, or the Mac re-advertising a beat after our one discovery pass — and
     * with no new network event arriving, the phone would otherwise sit idle on
     * the right network forever. See [RediscoveryWatchdog]. The loop dies with
     * serviceScope on onDestroy.
     */
    private fun startRediscoveryWatchdog() {
        serviceScope.launch {
            while (true) {
                kotlinx.coroutines.delay(REDISCOVERY_TICK_MS)
                if (rediscoveryWatchdog.onTick(isConnected.value)) {
                    Log.d(TAG, "Rediscovery watchdog: still disconnected — forcing fresh discovery")
                    forceRediscovery()
                }
            }
        }
    }

    /**
     * Drop the stale cached host and run a fresh discovery pass. Shared by the
     * rediscovery watchdog and the explicit [ACTION_REDISCOVER] trigger (app
     * brought to the foreground). Unlike [onNetworkChanged] this makes no
     * assumption about a network switch — it is the recovery action on its own.
     */
    private fun forceRediscovery() {
        webSocketClient.forgetHost()
        connectedHost.value = null
        nsdDiscovery.restart()
    }

    /**
     * Called when the device switches to a different network (e.g. work Wi-Fi
     * -> home Wi-Fi). The cached host is now on an unreachable network, so we
     * forget it and re-run discovery to find the peer's new address.
     *
     * Runs on the main thread — NetworkMonitor registers its callback with a
     * main-looper Handler, so NsdManager calls and client state mutations here
     * never happen on a binder thread.
     */
    private fun onNetworkChanged() {
        Log.d(TAG, "Network changed — forgetting stale host and restarting discovery")
        webSocketClient.forgetHost()
        connectedHost.value = null
        isConnected.value = false
        nsdDiscovery.restart()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_DISCOVERY -> {
                Log.d(TAG, "Starting NSD discovery")
                nsdDiscovery.startDiscovery()
            }
            ACTION_REDISCOVER -> {
                // App came to the foreground. If we're already connected this is
                // a no-op; otherwise kick a fresh discovery immediately instead
                // of waiting for the next watchdog tick, so opening the app feels
                // like it reconnects on the spot.
                if (!isConnected.value) {
                    Log.d(TAG, "Foreground rediscover requested — forcing fresh discovery")
                    forceRediscovery()
                }
            }
            ACTION_CONNECT -> {
                val host = intent.getStringExtra(EXTRA_HOST)
                val port = intent.getIntExtra(EXTRA_PORT, 0)
                val certFingerprint = intent.getStringExtra(EXTRA_CERT_FINGERPRINT) ?: ""
                if (host != null && port != 0) {
                    Log.d(TAG, "Connecting directly to $host:$port")
                    connectedHost.value = host
                    webSocketClient.shouldReconnect = true
                    webSocketClient.connect(host, port, certFingerprint)
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
                    Log.d(TAG, "Text share requested (${text.length} chars)")
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
                        // INVERTED MAC→PHONE FLOW (see HttpFileDownloader
                        // docs): instead of waiting for Mac to POST to our
                        // HttpFileServer on 8767 (blocked by macOS Local
                        // Network Privacy for ad-hoc signed apps), we
                        // fetch the file from Mac's HTTP server via GET.
                        // We make the outbound connection — Android has
                        // no LNP restriction — so the transfer always
                        // succeeds on the first try.
                        val host = connectedHost.value
                        val port = httpPort.value
                        if (host != null) {
                            serviceScope.launch {
                                transferFileName.value = offer.filename
                                transferIsSending.value = false
                                transferProgress.value = 0f
                                val tempFile = httpFileDownloader.download(
                                    host = host,
                                    port = port,
                                    certFingerprint = webSocketClient.certFingerprintInUse,
                                    transferId = transferId,
                                    filenameHint = offer.filename
                                ) { bytesReceived, totalBytes ->
                                    updateTransferProgress(offer.filename, bytesReceived, totalBytes)
                                }
                                if (tempFile != null) {
                                    val destDir = offer.destinationDir
                                    if (destDir != null) {
                                        finalizeReceivedFileToDir(offer.filename, offer.mimeType, destDir, tempFile)
                                    } else {
                                        finalizeReceivedFile(offer.filename, tempFile)
                                    }
                                } else {
                                    Log.e(TAG, "Download failed for ${offer.filename}")
                                    transferProgress.value = null
                                    transferFileName.value = null
                                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(4)
                                }
                            }
                        } else {
                            Log.w(TAG, "ACCEPT_FILE: no host, cannot download")
                        }
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
            ACTION_STOP_RING -> {
                stopRinging()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRinging()
        instance = null
        networkMonitor.stop()
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
                expectedMacPublicKey = pending.expectedMacPublicKeyBase64
                pendingPairCertFingerprint = pending.certFingerprint
                sendPairRequest(pending.deviceName, pending.phonePublicKeyBase64, pending.pairingToken)
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
            expectedMacPublicKey = null
            pendingPairCertFingerprint = null
            isConnected.value = false
            connectedSince.value = null
            macInfo.value = null
            macWallpaper.value = null
            // Keep connectedHost — WebSocket auto-reconnects to same host
            // status tracked via StateFlow, no notification update needed
        }

        webSocketClient.onMessage = { message ->
            handleIncomingMessage(message)
        }

        webSocketClient.onReconnectExhausted = {
            Log.d(TAG, "Reconnect exhausted — restarting discovery to find peer's new address")
            connectedHost.value = null
            nsdDiscovery.restart()
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
        nsdDiscovery.onServiceFound = handler@{ host, port, deviceName, httpPort, fingerprint, nsdCertFingerprint, mirrorPort ->
            if (fingerprint.isEmpty()) {
                Log.d(TAG, "NSD: $deviceName has no fingerprint — skipping")
                return@handler
            }
            val device = pairedDeviceStore.findByFingerprint(fingerprint)
            if (device == null) {
                Log.d(TAG, "NSD: $deviceName not paired (fp=${fingerprint.take(16)}...) — skipping")
                return@handler
            }
            // TLS pin gate: connecting without a pin (or with a stale one)
            // would only fail the handshake — surface re-pair guidance instead.
            val pinned = device.certFingerprint
            if (pinned.isEmpty()) {
                Log.w(TAG, "NSD: $deviceName paired without a TLS pin (pre-TLS pairing) — re-pair required")
                pairingIssue.value = getString(com.airbridge.R.string.repair_needed_no_pin, deviceName)
                return@handler
            }
            if (nsdCertFingerprint.isNotEmpty() && nsdCertFingerprint != pinned) {
                Log.w(TAG, "NSD: $deviceName advertises a different TLS certificate — re-pair required")
                pairingIssue.value = getString(com.airbridge.R.string.repair_needed_cert_changed, deviceName)
                return@handler
            }
            Log.d(TAG, "NSD: paired device $deviceName found at $host:$port — connecting (mirrorPort=$mirrorPort)")
            connectedHost.value = host
            connectedDeviceName.value = deviceName
            Companion.httpPort.value = httpPort
            currentMirrorPort = mirrorPort
            Companion.mirrorPortFlow.value = mirrorPort
            nsdDiscovery.stopDiscovery()
            webSocketClient.shouldReconnect = true
            webSocketClient.connect(host, port, pinned)
        }
    }

    private val pendingOffers = ConcurrentHashMap<String, Message.FileTransferOffer>() // transferId -> offer
    private val pendingOutgoingOffers = ConcurrentHashMap<String, kotlinx.coroutines.CompletableDeferred<Boolean>>()
    private var lastProgressNotifUpdate = 0L

    private fun setupHttpFileServer() {
        // Deliberately NOT started: the Mac cannot initiate outbound TCP to
        // the phone (macOS Local Network Privacy silently blocks it for
        // self-signed apps), so this inbound-POST server can never have a
        // client. Mac→phone file sends use the inverted pull path instead:
        // the phone fetches via GET /send/{id} from the Mac's HTTP server
        // (see HttpFileDownloader / ACTION_ACCEPT_FILE). The class and the
        // callback wiring below are kept for protocol symmetry — both paths
        // converge on updateTransferProgress / finalizeReceivedFile.
        httpFileServer.onProgress = { filename, bytesReceived, totalBytes ->
            updateTransferProgress(filename, bytesReceived.toLong(), totalBytes.toLong())
        }
        httpFileServer.onFileReceived = { filename, _, tempFile ->
            finalizeReceivedFile(filename, tempFile)
        }
        // Only the currently connected Mac may POST files; with no Mac
        // connected, everything in the LAN gets rejected.
        httpFileServer.isAllowedSender = { remote ->
            connectedHost.value?.let { isSameHost(remote, it) } ?: false
        }
    }

    /** Compares an incoming socket address with the connected Mac's host. */
    private fun isSameHost(remote: java.net.InetAddress, allowedHost: String): Boolean {
        // Strip the IPv6 zone index ("%wlan0") on both sides before comparing.
        val remoteAddr = remote.hostAddress?.substringBefore('%') ?: return false
        if (remoteAddr.equals(allowedHost.substringBefore('%'), ignoreCase = true)) return true
        return try {
            java.net.InetAddress.getAllByName(allowedHost).any { it == remote }
        } catch (_: Exception) {
            false
        }
    }

    /// Shared progress updater used by BOTH inbound POST (legacy
    /// `httpFileServer`) and outbound GET (`httpFileDownloader`) receive
    /// paths. Updates the UI StateFlows and the progress notification.
    private fun updateTransferProgress(filename: String, bytesReceived: Long, totalBytes: Long) {
        transferFileName.value = filename
        transferIsSending.value = false
        val progress = if (totalBytes > 0) bytesReceived.toFloat() / totalBytes else 0f
        transferProgress.value = progress

        // Throttle notification updates to max every 300ms
        val now = System.currentTimeMillis()
        if (now - lastProgressNotifUpdate >= 300 || (totalBytes > 0 && bytesReceived >= totalBytes)) {
            lastProgressNotifUpdate = now
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val sender = connectedDeviceName.value ?: "Mac"
            val sizeText = when {
                totalBytes > 1024 * 1024 -> String.format("%.1f MB", totalBytes / (1024.0 * 1024.0))
                totalBytes > 1024 -> String.format("%.0f KB", totalBytes / 1024.0)
                else -> "$totalBytes B"
            }
            val progressPercent = (progress * 100).toInt().coerceIn(0, 100)
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

    /// Shared finalization: moves the temp file into the user's Downloads
    /// folder, clears transfer state, fires the "file received" notification.
    /// Called by both the legacy inbound-POST path and the new GET path.
    private fun finalizeReceivedFile(filename: String, tempFile: File) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(4)
        serviceScope.launch {
            try {
                val prefs = getSharedPreferences("airbridge_prefs", MODE_PRIVATE)
                val folder = prefs.getString("download_folder", null)
                    ?: android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_DOWNLOADS
                    ).absolutePath + "/AirBridge"
                val dir = File(folder)
                if (!dir.exists()) dir.mkdirs()
                // Filename comes from the network — sanitize against traversal.
                val file = com.airbridge.files.SafeFileName.resolveIn(dir, filename)
                if (file == null) {
                    Log.w(TAG, "Rejected unsafe received filename")
                    tempFile.delete()
                    transferProgress.value = null
                    transferFileName.value = null
                    return@launch
                }
                tempFile.copyTo(file, overwrite = true)
                tempFile.delete()
                Log.d(TAG, "File received: ${file.absolutePath}")
                addActivity(ActivityItem("file_received", filename, System.currentTimeMillis()))
                transferProgress.value = null
                transferFileName.value = null

                // Tapping the "File received" notification should hand the
                // file off to whatever app the user has registered for that
                // MIME type (image viewer, PDF reader, etc.) — NOT drag them
                // into AirBridge which has no per-file viewer. Build a
                // content:// URI via FileProvider, attach it to an
                // ACTION_VIEW intent with the MIME type inferred from the
                // file extension, and grant the receiver one-shot read
                // permission. Fall back to opening AirBridge if FileProvider
                // fails for any reason (unusual download folder, etc.).
                val openIntent = buildOpenFileIntent(file)
                val contentIntent = openIntent?.let {
                    android.app.PendingIntent.getActivity(
                        this@AirbridgeService, file.absolutePath.hashCode(), it,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                    )
                } ?: openAppPendingIntent()

                val notif = Notification.Builder(this@AirbridgeService, CHANNEL_FILES_ID)
                    .setContentTitle(getString(com.airbridge.R.string.notification_title_file_received))
                    .setContentText(filename)
                    .setSmallIcon(com.airbridge.R.drawable.ic_notification)
                    .setContentIntent(contentIntent)
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

    /// Files-browser upload variant: writes the received temp file into a
    /// SAF-granted folder on the phone (chosen on Mac via destinationDir)
    /// using FilesProvider.createFile, instead of the default Downloads
    /// location. Mirrors finalizeReceivedFile's notification/state UX.
    private fun finalizeReceivedFileToDir(filename: String, mimeType: String, destinationDir: String, tempFile: File) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(4)
        serviceScope.launch {
            try {
                val mime = mimeType.ifBlank { "application/octet-stream" }
                // Filename comes from the network — keep only a safe segment.
                val safeName = com.airbridge.files.SafeFileName.sanitize(filename)
                if (safeName == null) {
                    Log.w(TAG, "Rejected unsafe received filename")
                    tempFile.delete()
                    transferProgress.value = null
                    transferFileName.value = null
                    return@launch
                }
                val created = filesProvider.createFile(destinationDir, safeName, mime)
                if (created == null) {
                    Log.e(TAG, "createFile failed for $destinationDir/$filename — falling back to Downloads")
                    finalizeReceivedFile(filename, tempFile)
                    return@launch
                }
                val (newUri, out) = created
                try {
                    out.use { os -> tempFile.inputStream().use { it.copyTo(os) } }
                } catch (e: Exception) {
                    Log.e(TAG, "Copy to file failed, removing empty file $newUri", e)
                    try { newUri.path?.let { File(it).delete() } } catch (de: Exception) {
                        Log.w(TAG, "Could not delete empty file $newUri", de)
                    }
                    transferProgress.value = null
                    transferFileName.value = null
                    return@launch
                }
                tempFile.delete()
                Log.d(TAG, "File received into dir: $destinationDir/$filename")
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
                Log.e(TAG, "File save to SAF dir failed", e)
                transferProgress.value = null
                transferFileName.value = null
            }
        }
    }

    /// Build an ACTION_VIEW intent that asks the system to open the given
    /// file with whatever app the user has set for that MIME type. Returns
    /// null if the URI / MIME type can't be resolved, in which case the
    /// caller should fall back to opening the main app.
    private fun buildOpenFileIntent(file: File): Intent? {
        return try {
            val authority = "$packageName.fileprovider"
            val uri = androidx.core.content.FileProvider.getUriForFile(this, authority, file)
            val extension = file.extension.lowercase()
            val mimeType = android.webkit.MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension) ?: "*/*"
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "buildOpenFileIntent failed for ${file.absolutePath}", e)
            null
        }
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

        // Tapping the notification body opens FileOfferDialogActivity (a
        // transparent activity hosting a Material3 AlertDialog with the same
        // Accept/Reject choices). This gives the user a focused confirmation
        // surface instead of dumping them into the main app where the offer
        // isn't even visible. The dialog reuses the same service actions as
        // the notification's action buttons, so both paths stay in sync.
        val dialogIntent = Intent(this, com.airbridge.ui.FileOfferDialogActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(com.airbridge.ui.FileOfferDialogActivity.EXTRA_TRANSFER_ID, offer.transferId)
            putExtra(com.airbridge.ui.FileOfferDialogActivity.EXTRA_FILENAME, offer.filename)
            putExtra(com.airbridge.ui.FileOfferDialogActivity.EXTRA_FILE_SIZE, offer.fileSize)
            putExtra(com.airbridge.ui.FileOfferDialogActivity.EXTRA_SENDER, sender)
        }
        val dialogPendingIntent = android.app.PendingIntent.getActivity(
            this, notifId + 100000, dialogIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val notif = Notification.Builder(this, CHANNEL_FILES_ID)
            .setContentTitle(getString(com.airbridge.R.string.notification_accept_file, sender))
            .setContentText(getString(com.airbridge.R.string.notification_accept_file_detail, offer.filename, sizeText))
            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
            .setContentIntent(dialogPendingIntent)
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
                Log.d(TAG, "Received clipboard: type=${message.contentType.value} (${message.data.length} chars)")
                if (message.contentType == ContentType.PLAIN_TEXT || message.contentType == ContentType.HTML) {
                    val hash = sha256(message.data)
                    lastRemoteClipHash = hash
                    clipboardSync.setClipboard(message.data)
                    addActivity(ActivityItem("clipboard_received", "", System.currentTimeMillis()))
                    Log.d(TAG, "Applied remote clipboard update")
                }
            }
            is Message.AuthResponse -> {
                if (message.protocolVersion != Message.PROTOCOL_VERSION) {
                    Log.w(TAG, "Protocol version mismatch: Mac speaks ${message.protocolVersion}, " +
                        "we speak ${Message.PROTOCOL_VERSION}")
                }
                if (message.accepted) {
                    Log.d(TAG, "Auth accepted — connection authenticated (mirrorPort=${message.mirrorPort})")
                    // Refresh the mirror port from the application channel on every
                    // (re)connect. The NSD/Bonjour record is one-shot and lost on process
                    // restart or WebSocket auto-reconnect, which left mirrorPort null and
                    // broke phone-initiated screen sharing ("connect to your Mac").
                    message.mirrorPort?.let { port ->
                        currentMirrorPort = port
                        mirrorPortFlow.value = port
                    }
                    isConnected.value = true
                    connectedSince.value = System.currentTimeMillis()
                    pairingIssue.value = null
                    // Pull the Mac's system info + wallpaper for the Home monitor.
                    webSocketClient.send(Message.MacInfoRequest)
                    webSocketClient.send(Message.MacWallpaperRequest)
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
                val expectedKey = expectedMacPublicKey
                expectedMacPublicKey = null
                val pairCertFingerprint = pendingPairCertFingerprint
                pendingPairCertFingerprint = null
                if (message.accepted) {
                    // Verify the key in the PairResponse against the key scanned
                    // from the Mac's QR code. A mismatch (or a PairResponse with
                    // no pairing in progress) means an active MITM may be
                    // substituting its own key — reject and disconnect.
                    if (expectedKey == null || expectedKey != message.publicKey) {
                        Log.e(TAG, "PairResponse public key does not match the QR-scanned key — rejecting pairing (possible MITM)")
                        // Drop the entry stored optimistically at QR-scan time;
                        // pairing did not complete, leave no trusted key behind.
                        expectedKey?.let { pairedDeviceStore.remove(com.airbridge.security.KeyManager.fingerprintOf(it)) }
                        connectedDeviceName.value = null
                        webSocketClient.shouldReconnect = false
                        webSocketClient.disconnect()
                        isConnected.value = false
                        return
                    }
                    connectedDeviceName.value = message.deviceName
                    // Update stored device name with Mac's actual name
                    pairedDeviceStore.add(
                        com.airbridge.security.PairedDevice(
                            deviceName = message.deviceName,
                            publicKeyBase64 = message.publicKey,
                            publicKeyFingerprint = com.airbridge.security.KeyManager.fingerprintOf(message.publicKey),
                            pairedAt = System.currentTimeMillis(),
                            certFingerprint = pairCertFingerprint ?: ""
                        )
                    )
                    isConnected.value = true
                    connectedSince.value = System.currentTimeMillis()
                    pairingIssue.value = null
                    // pairing status tracked via StateFlow
                } else {
                    connectedDeviceName.value = null
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
            is Message.GalleryPreviewRequest -> {
                Log.d(TAG, "GalleryPreviewRequest: photoId=${message.photoId} maxSize=${message.maxSize}")
                serviceScope.launch {
                    val data = galleryProvider.getPreview(message.photoId, message.maxSize)
                    if (data != null) {
                        val response = Message.GalleryPreviewResponse(message.photoId, data)
                        webSocketClient.send(response)
                    } else {
                        Log.d(TAG, "getPreview returned null for ${message.photoId}")
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
                                certFingerprint = webSocketClient.certFingerprintInUse,
                                uri = uri,
                                contentResolver = applicationContext.contentResolver
                            ) { _, _ -> }
                        }
                    }
                }
            }
            is Message.FilesListRequest -> {
                serviceScope.launch {
                    try {
                        if (!filesProvider.hasGrant()) {
                            webSocketClient.send(
                                Message.FilesListResponse(
                                    path = message.path,
                                    entries = emptyList(),
                                    totalCount = 0,
                                    page = message.page,
                                    needsPermission = true
                                )
                            )
                        } else {
                            val (entries, total) = if (message.query.isBlank()) {
                                filesProvider.listDir(
                                    message.path, message.page, message.pageSize,
                                    message.sortBy, message.sortDir, message.foldersFirst
                                )
                            } else {
                                filesProvider.searchDir(
                                    message.query, message.page, message.pageSize,
                                    message.sortBy, message.sortDir, message.foldersFirst
                                )
                            }
                            webSocketClient.send(
                                Message.FilesListResponse(
                                    path = message.path,
                                    entries = entries,
                                    totalCount = total,
                                    page = message.page,
                                    needsPermission = false
                                )
                            )
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "FilesListRequest failed", e)
                    }
                }
            }
            is Message.FileDeleteRequest -> {
                serviceScope.launch {
                    try {
                        if (!filesProvider.hasGrant()) {
                            webSocketClient.send(
                                Message.FileDeleteResponse(message.path, false, "no_permission")
                            )
                        } else {
                            val ok = filesProvider.delete(message.path)
                            webSocketClient.send(
                                Message.FileDeleteResponse(message.path, ok, if (ok) null else "delete_failed")
                            )
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "FileDeleteRequest failed", e)
                    }
                }
            }
            is Message.FileThumbnailRequest -> {
                serviceScope.launch {
                    val data = filesProvider.getThumbnail(message.path)
                    if (data != null) {
                        webSocketClient.send(Message.FileThumbnailResponse(path = message.path, data = data))
                    }
                }
            }
            is Message.FolderStatsRequest -> {
                serviceScope.launch {
                    try {
                        val (dirCount, fileCount, totalSize) = filesProvider.folderStats(message.path)
                        webSocketClient.send(
                            Message.FolderStatsResponse(message.path, dirCount, fileCount, totalSize)
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "FolderStatsRequest failed", e)
                    }
                }
            }
            is Message.FileDownloadRequest -> {
                serviceScope.launch {
                    val uri = filesProvider.fileUri(message.path)
                    val host = connectedHost.value
                    val port = httpPort.value
                    if (uri != null && host != null) {
                        httpFileUploader.upload(
                            host = host,
                            port = port,
                            certFingerprint = webSocketClient.certFingerprintInUse,
                            uri = uri,
                            contentResolver = applicationContext.contentResolver
                        ) { _, _ -> }
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
            is Message.NotificationReply -> {
                val ok = com.airbridge.notification.NotificationRelayService
                    .sendReply(message.notificationKey, message.text)
                if (!ok) Log.w(TAG, "NotificationReply: brak akcji dla key=${message.notificationKey}")
            }
            is Message.MirrorStartRequest -> {
                val host = connectedHost.value
                val mirrorPort = currentMirrorPort
                if (host == null || mirrorPort == null) {
                    Log.w(TAG, "MirrorStartRequest received but host=$host mirrorPort=$mirrorPort — ignoring")
                    return
                }
                getSharedPreferences("airbridge_prefs", MODE_PRIVATE).edit().putString("mirror_token", message.token).apply()
                val tokenBytes = android.util.Base64.decode(message.token, android.util.Base64.NO_WRAP)
                val intent = Intent(this, com.airbridge.mirror.MirrorActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra(com.airbridge.mirror.MirrorActivity.EXTRA_HOST, host)
                    putExtra(com.airbridge.mirror.MirrorActivity.EXTRA_PORT, mirrorPort)
                    putExtra(com.airbridge.mirror.MirrorActivity.EXTRA_TOKEN, tokenBytes)
                    putExtra(com.airbridge.mirror.MirrorActivity.EXTRA_CERT_FINGERPRINT, webSocketClient.certFingerprintInUse)
                }
                startActivity(intent)
                Log.d(TAG, "MirrorStartRequest: launched MirrorActivity → $host:$mirrorPort")
            }
            is Message.ReverseMirrorStart -> {
                val host = connectedHost.value
                val mirrorPort = currentMirrorPort
                if (host == null || mirrorPort == null) {
                    Log.w(TAG, "ReverseMirrorStart received but host=$host mirrorPort=$mirrorPort — ignoring")
                    return
                }
                getSharedPreferences("airbridge_prefs", MODE_PRIVATE).edit().putString("mirror_token", message.token).apply()
                val tokenBytes = android.util.Base64.decode(message.token, android.util.Base64.NO_WRAP)
                val intent = Intent(this, com.airbridge.mirror.ReverseMirrorActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra(com.airbridge.mirror.ReverseMirrorActivity.EXTRA_HOST, host)
                    putExtra(com.airbridge.mirror.ReverseMirrorActivity.EXTRA_PORT, mirrorPort)
                    putExtra(com.airbridge.mirror.ReverseMirrorActivity.EXTRA_TOKEN, tokenBytes)
                    putExtra(com.airbridge.mirror.ReverseMirrorActivity.EXTRA_MODE, message.mode)
                    putExtra(com.airbridge.mirror.ReverseMirrorActivity.EXTRA_CERT_FINGERPRINT, webSocketClient.certFingerprintInUse)
                }
                startActivity(intent)
                Log.d(TAG, "ReverseMirrorStart: launched ReverseMirrorActivity → $host:$mirrorPort mode=${message.mode}")
            }
            is Message.MirrorStop -> {
                val intent = Intent(this, com.airbridge.mirror.MirrorService::class.java).apply {
                    action = com.airbridge.mirror.MirrorService.ACTION_STOP
                }
                startService(intent)
                Log.d(TAG, "MirrorStop: sent ACTION_STOP to MirrorService")
            }
            is Message.MirrorError -> {
                Log.w(TAG, "Mac reported mirror error: ${message.reason}")
            }
            is Message.PhoneRing -> startRinging()
            is Message.PhoneRingStop -> stopRinging()
            is Message.DeviceInfoRequest -> {
                serviceScope.launch {
                    try {
                        val info = com.airbridge.device.DeviceInfoProvider.collect(applicationContext)
                        webSocketClient.send(Message.DeviceInfoResponse(info))
                    } catch (e: Exception) {
                        Log.e(TAG, "DeviceInfoRequest failed", e)
                    }
                }
            }
            is Message.MacInfoResponse -> {
                macInfo.value = message.info
            }
            is Message.MacWallpaperResponse -> {
                macWallpaper.value = message.imageBase64.takeIf { it.isNotEmpty() }
            }
            is Message.WallpaperRequest -> {
                serviceScope.launch {
                    try {
                        val image = com.airbridge.device.WallpaperProvider.getWallpaperJpegBase64(applicationContext)
                        webSocketClient.send(Message.WallpaperResponse(image))
                    } catch (e: Exception) {
                        Log.e(TAG, "WallpaperRequest failed", e)
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
                certFingerprint = webSocketClient.certFingerprintInUse,
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
                        transferSpeedHistory.update { prev ->
                            val history = prev.toMutableList()
                            history.add(normalized)
                            if (history.size > 60) history.removeAt(0)
                            history
                        }
                    }

                    // Update notification every 500ms
                    if (now - lastNotifUpdate >= 500) {
                        lastNotifUpdate = now
                        val speedText = com.airbridge.util.formatTransferSpeed(speed)
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

    // MARK: - Ring (znajdź telefon)

    private var ringPlayer: android.media.MediaPlayer? = null
    private var ringVibrator: android.os.Vibrator? = null
    private var savedAlarmVolume: Int? = null
    private val ringHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val ringStopRunnable = Runnable { stopRinging() }

    /**
     * Głośny alarm na STREAM_ALARM (omija tryb cichy) + wibracje, auto-stop po 30 s.
     *
     * Odtwarzamy przez [android.media.MediaPlayer], NIE przez RingtoneManager:
     * `Ringtone.stop()` na zapętlonym alarmie potrafi nie zatrzymać dźwięku na
     * One UI (Samsung), więc przycisk „Zatrzymaj" był nieskuteczny. MediaPlayer
     * daje deterministyczne stop()/release().
     */
    private fun startRinging() {
        if (ringPlayer?.isPlaying == true) return
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            savedAlarmVolume = audio.getStreamVolume(android.media.AudioManager.STREAM_ALARM)
            audio.setStreamVolume(
                android.media.AudioManager.STREAM_ALARM,
                audio.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM),
                0
            )
            val uri = android.media.RingtoneManager.getActualDefaultRingtoneUri(this, android.media.RingtoneManager.TYPE_ALARM)
                ?: android.media.RingtoneManager.getActualDefaultRingtoneUri(this, android.media.RingtoneManager.TYPE_RINGTONE)
                ?: android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
            ringPlayer = android.media.MediaPlayer().apply {
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AirbridgeService, uri)
                isLooping = true
                setOnErrorListener { _, _, _ -> stopRinging(); true }
                prepare()
                start()
            }
            startVibration()
            showRingNotification()
            ringHandler.removeCallbacks(ringStopRunnable)
            ringHandler.postDelayed(ringStopRunnable, 30_000)
            Log.d(TAG, "PhoneRing: started")
        } catch (e: Exception) {
            Log.e(TAG, "startRinging failed", e)
            stopRinging()
        }
    }

    private fun startVibration() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
        }
        ringVibrator = vibrator
        val effect = android.os.VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0)
        vibrator.vibrate(effect)
    }

    private fun stopRinging() {
        val wasRinging = ringPlayer != null || savedAlarmVolume != null
        ringHandler.removeCallbacks(ringStopRunnable)
        try { ringPlayer?.stop() } catch (_: Exception) {}
        try { ringPlayer?.release() } catch (_: Exception) {}
        ringPlayer = null
        try { ringVibrator?.cancel() } catch (_: Exception) {}
        ringVibrator = null
        savedAlarmVolume?.let { vol ->
            try {
                val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                audio.setStreamVolume(android.media.AudioManager.STREAM_ALARM, vol, 0)
            } catch (_: Exception) {}
        }
        savedAlarmVolume = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(RING_NOTIFICATION_ID)
        // Powiadom Maca, że dzwonek ucichł (przycisk na telefonie, auto-stop po 30 s
        // lub żądanie z Maca) — żeby przycisk w pasku menu wrócił do „Zadzwoń".
        if (wasRinging) {
            try { webSocketClient.send(Message.PhoneRingStop) } catch (_: Exception) {}
        }
        Log.d(TAG, "PhoneRing: stopped")
    }

    private fun showRingNotification() {
        val stopPI = android.app.PendingIntent.getService(
            this, RING_NOTIFICATION_ID,
            Intent(this, AirbridgeService::class.java).apply { action = ACTION_STOP_RING },
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        val stopAction = Notification.Action.Builder(
            null as android.graphics.drawable.Icon?,
            getString(com.airbridge.R.string.notification_ring_stop), stopPI
        ).build()
        val notif = Notification.Builder(this, CHANNEL_FILES_ID)
            .setContentTitle(getString(com.airbridge.R.string.notification_ring_title))
            .setContentText(getString(com.airbridge.R.string.notification_ring_text))
            .setSmallIcon(com.airbridge.R.drawable.ic_notification)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(stopPI)
            .addAction(stopAction)
            .build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(RING_NOTIFICATION_ID, notif)
    }

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
