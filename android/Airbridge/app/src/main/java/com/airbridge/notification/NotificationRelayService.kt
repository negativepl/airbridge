package com.airbridge.notification

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import com.airbridge.service.AirbridgeService
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Czyta powiadomienia systemowe i (po odsianiu szumu) przekazuje je na Maca przez
 * AirbridgeService. Wymaga uprawnienia BIND_NOTIFICATION_LISTENER_SERVICE (włączane
 * przez użytkownika w ustawieniach systemowych).
 */
class NotificationRelayService : NotificationListenerService() {

    // Ikony apek nie zmieniają się — licz raz per pakiet. ConcurrentHashMap, bo
    // onNotificationPosted może przychodzić z różnych wątków binder poola
    // (worst case przy wyścigu: podwójne zakodowanie ikony — akceptowalne).
    private val iconCache = ConcurrentHashMap<String, String>()

    override fun onListenerConnected() {
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
        replyActions.clear()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        replyActions.remove(sbn.key)
    }

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

        // Akcja z RemoteInput = możliwość odpowiedzi inline (np. WhatsApp).
        val replyAction = n.actions?.firstOrNull { !it.remoteInputs.isNullOrEmpty() }
        if (replyAction != null) {
            replyActions[sbn.key] = replyAction
        } else {
            replyActions.remove(sbn.key)
        }

        AirbridgeService.relayNotification(
            packageName = sbn.packageName,
            appName = appName,
            title = title ?: "",
            text = text ?: "",
            timestamp = sbn.postTime,
            appIcon = icon,
            notificationKey = sbn.key,
            canReply = replyAction != null
        )
    }

    /** Wypełnia RemoteInput tekstem i odpala PendingIntent akcji reply na telefonie. */
    private fun fireReply(action: Notification.Action, text: String): Boolean {
        val remoteInputs = action.remoteInputs ?: return false
        val intent = Intent()
        val results = Bundle()
        for (ri in remoteInputs) results.putCharSequence(ri.resultKey, text)
        RemoteInput.addResultsToIntent(remoteInputs, intent, results)
        return try {
            action.actionIntent.send(this, 0, intent)
            true
        } catch (e: PendingIntent.CanceledException) {
            Log.e("NotificationRelay", "reply send failed", e)
            false
        }
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

    companion object {
        @Volatile
        private var instance: NotificationRelayService? = null

        /** key (sbn.key) → akcja reply z RemoteInput. Trzymane, bo PendingIntenta
         *  nie da się serializować — odpalamy go po stronie telefonu na żądanie.
         *  ConcurrentHashMap: pisane z wątku binder listenera, czytane z wątku
         *  WebSocketa (sendReply). */
        private val replyActions = ConcurrentHashMap<String, Notification.Action>()

        /** Most z AirbridgeService: wpisany na Macu tekst → odpal reply na telefonie. */
        fun sendReply(notificationKey: String, text: String): Boolean {
            val action = replyActions[notificationKey] ?: return false
            return instance?.fireReply(action, text) ?: false
        }
    }
}
