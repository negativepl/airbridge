package com.airbridge.notification

import android.app.Notification
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import com.airbridge.service.AirbridgeService
import java.io.ByteArrayOutputStream

/**
 * Czyta powiadomienia systemowe i (po odsianiu szumu) przekazuje je na Maca przez
 * AirbridgeService. Wymaga uprawnienia BIND_NOTIFICATION_LISTENER_SERVICE (włączane
 * przez użytkownika w ustawieniach systemowych).
 */
class NotificationRelayService : NotificationListenerService() {

    // Ikony apek nie zmieniają się — licz raz per pakiet.
    private val iconCache = HashMap<String, String>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (!shouldRelayNotification(n.flags, sbn.packageName, packageName, title, text)) return

        val pm = applicationContext.packageManager
        val appName = try {
            pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString()
        } catch (e: Exception) {
            sbn.packageName
        }

        val icon = iconCache.getOrPut(sbn.packageName) {
            try {
                encodeAppIcon(pm.getApplicationIcon(sbn.packageName))
            } catch (e: Exception) {
                ""
            }
        }

        AirbridgeService.relayNotification(
            packageName = sbn.packageName,
            appName = appName,
            title = title ?: "",
            text = text ?: "",
            timestamp = sbn.postTime,
            appIcon = icon
        )
    }

    /** Drawable ikony aplikacji → 96px PNG → base64. */
    private fun encodeAppIcon(drawable: Drawable): String {
        val size = 96
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            bmp
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }
}
