package com.airbridge.mirror

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.core.content.IntentCompat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import com.airbridge.R

class MirrorService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var encoder: ScreenEncoder? = null
    private var client: MirrorClient? = null
    @Volatile private var encoderStarted = false
    @Volatile private var sessionGeneration = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent ?: return START_NOT_STICKY
        when (intent.action) {
            ACTION_START -> startMirror(intent)
            ACTION_STOP -> { stopMirror(); stopSelf() }
        }
        return START_NOT_STICKY
    }

    private fun startMirror(intent: Intent) {
        sessionGeneration += 1
        val generation = sessionGeneration
        stopMirror()
        startForegroundCompat()
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = IntentCompat.getParcelableExtra(intent, EXTRA_RESULT_DATA, Intent::class.java) ?: return stopSelf()
        val host = intent.getStringExtra(EXTRA_HOST) ?: return stopSelf()
        val port = intent.getIntExtra(EXTRA_PORT, 0)
        val token = intent.getByteArrayExtra(EXTRA_TOKEN) ?: return stopSelf()
        val certFingerprint = intent.getStringExtra(EXTRA_CERT_FINGERPRINT) ?: ""

        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = mpm.getMediaProjection(resultCode, data) ?: return stopSelf()
        mediaProjection = projection

        val (w, h) = displayDimensions()

        client = MirrorClient(
            onTap = { x, y ->
                MirrorAccessibilityService.dispatchTap(this, x, y)
            },
            host = host, port = port, certFingerprint = certFingerprint, pairingToken = token,
            screenWidth = w.toUInt(), screenHeight = h.toUInt(), orientation = 0u,
            onAck = { ack ->
                if (generation != sessionGeneration) return@MirrorClient
                if (encoderStarted) return@MirrorClient
                encoderStarted = true
                val targetW = ack.targetWidth.toInt().coerceAtLeast(1)
                val targetH = ack.targetHeight.toInt().coerceAtLeast(1)
                val enc = ScreenEncoder(
                    mediaProjection = projection,
                    width = targetW, height = targetH,
                    fps = ack.fps.toInt(),
                    bitrateBps = ack.targetBitrateBps.toInt(),
                    keyframeIntervalSeconds = ack.keyframeIntervalSeconds.toInt(),
                    useHEVC = ack.codec.toInt() == 1
                ) { msg -> client?.send(msg) }
                enc.start()
                encoder = enc
            },
            onDisconnect = {
                if (generation != sessionGeneration) return@MirrorClient
                stopSelf()
            }
        ).also { it.connect() }
    }

    private fun stopMirror() {
        encoderStarted = false
        encoder?.stop(); encoder = null
        client?.close(); client = null
        mediaProjection?.stop(); mediaProjection = null
    }

    override fun onDestroy() { stopMirror(); super.onDestroy() }

    private fun startForegroundCompat() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL, "Mirror", NotificationManager.IMPORTANCE_LOW))
        val stopIntent = Intent(this, MirrorService::class.java).setAction(ACTION_STOP)
        val stopPi = PendingIntent.getService(this, 0, stopIntent, PendingIntent.FLAG_IMMUTABLE)
        val notif = Notification.Builder(this, CHANNEL)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Mirror trwa")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .addAction(Notification.Action.Builder(null, "Stop", stopPi).build())
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
    }

    @Suppress("DEPRECATION")
    private fun displayDimensions(): Pair<Int, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics().also { wm.defaultDisplay.getRealMetrics(it) }
        return metrics.widthPixels to metrics.heightPixels
    }

    companion object {
        const val ACTION_START = "com.airbridge.mirror.START"
        const val ACTION_STOP = "com.airbridge.mirror.STOP"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_TOKEN = "token"
        const val EXTRA_CERT_FINGERPRINT = "certFingerprint"
        private const val CHANNEL = "mirror"
        private const val NOTIF_ID = 4711
    }
}
