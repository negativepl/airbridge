package com.airbridge.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.os.Build
import com.airbridge.R
import com.airbridge.service.AirbridgeService
import com.airbridge.ui.MainActivity

/**
 * A fake incoming call for debug builds, so the call flow can be tried without
 * anyone ringing: it posts a real Notification.CallStyle notification, which
 * takes exactly the path the phone app's call notification takes (listener →
 * Mac → Answer / Decline pressed back here).
 *
 *   adb shell am start-foreground-service -n com.airbridge/.service.AirbridgeService \
 *       -a com.airbridge.action.DEBUG_FAKE_CALL --es caller "Jan Kowalski"
 *   … -a com.airbridge.action.DEBUG_FAKE_CALL_END     (the caller hangs up)
 *
 * Needs the full-screen-intent permission (debug manifest), granted once with
 *   adb shell appops set com.airbridge USE_FULL_SCREEN_INTENT allow
 */
object DebugCall {
    const val TAG = "airbridge_debug_call"
    private const val ID = 4711
    private const val CHANNEL = "debug_call"

    fun ring(context: Context, caller: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val person = Person.Builder().setName(caller).setImportant(true).build()
        val style = Notification.CallStyle.forIncomingCall(
            person,
            serviceIntent(context, AirbridgeService.ACTION_DEBUG_FAKE_CALL_END, 1),
            serviceIntent(context, AirbridgeService.ACTION_DEBUG_FAKE_CALL_ANSWERED, 2)
        )
        post(context, caller, style)
    }

    /** Answered: the notification turns into an ongoing call, as the phone app's does. */
    fun answered(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val nm = context.getSystemService(NotificationManager::class.java)
        val caller = nm.activeNotifications.firstOrNull { it.tag == TAG }
            ?.notification?.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: "Debug"
        val person = Person.Builder().setName(caller).build()
        val style = Notification.CallStyle.forOngoingCall(
            person, serviceIntent(context, AirbridgeService.ACTION_DEBUG_FAKE_CALL_END, 1)
        )
        post(context, caller, style)
    }

    fun end(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(TAG, ID)
    }

    // Both callers return below Android 12, where CallStyle does not exist.
    @androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
    private fun post(context: Context, caller: String, style: Notification.CallStyle) {
        val nm = context.getSystemService(NotificationManager::class.java)
        // Silent: the point is the Mac side, not a ringing phone on the desk.
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Debug call", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) }
        )
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(caller)
            .setCategory(Notification.CATEGORY_CALL)
            .setStyle(style)
            // CallStyle needs a full-screen intent (or a foreground service).
            // Without the full-screen permission it only shows as heads-up.
            .setFullScreenIntent(open, true)
            .setOngoing(true)
            .build()
        // A refused post (permission not granted) must not take the service down.
        try {
            nm.notify(TAG, ID, notification)
        } catch (e: IllegalArgumentException) {
            android.util.Log.w("DebugCall", "Fake call not posted — grant USE_FULL_SCREEN_INTENT via adb appops", e)
        }
    }

    private fun serviceIntent(context: Context, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            context, requestCode,
            Intent(context, AirbridgeService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
}
