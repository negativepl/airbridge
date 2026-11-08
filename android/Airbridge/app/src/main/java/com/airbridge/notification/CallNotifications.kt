package com.airbridge.notification

import android.app.Notification
import android.app.PendingIntent
import android.os.Build
import android.os.Bundle
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.os.BundleCompat
import com.airbridge.service.AirbridgeService
import java.util.concurrent.ConcurrentHashMap

/**
 * Incoming calls, read from the phone app's own call notification. No telephony
 * permission is needed: the notification already carries who is calling and
 * the Answer / Decline buttons, and the notification listener can see it.
 *
 * Two shapes are understood:
 * - Notification.CallStyle (Android 12+): call type, caller and the answer /
 *   decline intents are explicit extras;
 * - an older "call" category notification: ringing is recognised by an action
 *   titled like Answer, and the buttons are matched by their titles.
 *
 * Answering from the Mac presses the same button on the phone, so the call
 * itself stays on the phone (its speaker, earpiece or connected headphones).
 */
object CallNotifications {
    private const val TAG = "CallNotifications"

    // Notification.EXTRA_CALL_TYPE & co. are API 31; the string keys work on
    // every version and read nothing on phones that never set them.
    private const val EXTRA_CALL_TYPE = "android.callType"
    private const val EXTRA_CALL_PERSON = "android.callPerson"
    private const val EXTRA_ANSWER_INTENT = "android.answerIntent"
    private const val EXTRA_DECLINE_INTENT = "android.declineIntent"
    private const val CALL_TYPE_INCOMING = 1

    private class Ringing(val caller: String, val answer: PendingIntent?, val decline: PendingIntent?)

    /** sbn.key → the call it rings for. Written from the listener's binder thread, read from the socket's. */
    private val ringing = ConcurrentHashMap<String, Ringing>()

    /**
     * A notification was posted or updated. Returns true when it is a call
     * notification (ringing or not), so the caller does not also relay it as
     * an ordinary notification.
     */
    fun onPosted(sbn: StatusBarNotification): Boolean {
        val n = sbn.notification ?: return false
        val extras = n.extras
        val callType = if (extras.containsKey(EXTRA_CALL_TYPE)) extras.getInt(EXTRA_CALL_TYPE, -1) else null
        val actionTitles = n.actions?.map { it.title?.toString().orEmpty() }.orEmpty()
        val (answerIndex, declineIndex) = matchCallActions(actionTitles)
        val isCall = n.category == Notification.CATEGORY_CALL || callType != null
        if (!isCall) return false

        val isRinging = isRingingCall(callType, answerIndex != null)
        if (!isRinging) {
            // Answered (now an ongoing call) or screened: no longer ringing.
            end(sbn.key)
            return true
        }

        val caller = callerName(extras)
        val answer = BundleCompat.getParcelable(extras, EXTRA_ANSWER_INTENT, PendingIntent::class.java)
            ?: answerIndex?.let { n.actions[it].actionIntent }
        val decline = BundleCompat.getParcelable(extras, EXTRA_DECLINE_INTENT, PendingIntent::class.java)
            ?: declineIndex?.let { n.actions[it].actionIntent }
        val previous = ringing.put(sbn.key, Ringing(caller, answer, decline))
        // The phone app re-posts the notification while it rings; tell the Mac
        // once per call, and again only if what it shows changed.
        if (previous == null || previous.caller != caller ||
            (previous.answer != null) != (answer != null) || (previous.decline != null) != (decline != null)
        ) {
            Log.i(TAG, "Incoming call (callStyle=${callType != null}, answer=${answer != null}, decline=${decline != null})")
            AirbridgeService.sendCallIncoming(sbn.key, caller, canAnswer = answer != null, canDecline = decline != null)
        }
        return true
    }

    fun onRemoved(key: String) = end(key)

    /** The call stopped ringing on the phone: answered there, declined, or the caller hung up. */
    private fun end(key: String) {
        if (ringing.remove(key) != null) {
            Log.i(TAG, "Call stopped ringing")
            AirbridgeService.sendCallEnded(key)
        }
    }

    /** The Mac pressed Answer or Decline. False when that call or button is gone. */
    fun perform(callId: String, answer: Boolean): Boolean {
        val call = ringing[callId] ?: return false
        val intent = (if (answer) call.answer else call.decline) ?: return false
        return try {
            intent.send()
            true
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "Call action no longer valid", e)
            false
        }
    }

    /** Calls still ringing, e.g. to announce to a Mac that just connected. */
    fun forEachRinging(block: (callId: String, caller: String, canAnswer: Boolean, canDecline: Boolean) -> Unit) {
        ringing.forEach { (key, call) -> block(key, call.caller, call.answer != null, call.decline != null) }
    }

    fun clear() = ringing.clear()

    private fun callerName(extras: Bundle): String {
        val person = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            BundleCompat.getParcelable(extras, EXTRA_CALL_PERSON, android.app.Person::class.java)?.name?.toString()
        } else null
        return person?.takeIf { it.isNotBlank() }
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.takeIf { it.isNotBlank() }
            ?: ""
    }

    /**
     * Ringing: a CallStyle notification of the incoming type, or, without
     * CallStyle, a call notification that offers to answer.
     */
    internal fun isRingingCall(callType: Int?, hasAnswerAction: Boolean): Boolean =
        if (callType != null) callType == CALL_TYPE_INCOMING else hasAnswerAction

    private val answerWords = listOf("answer", "accept", "odbierz", "odebrać", "odebrac")
    private val declineWords = listOf("decline", "reject", "dismiss", "odrzuć", "odrzuc")

    /** Indexes of the Answer and Decline actions among the notification's action titles. */
    internal fun matchCallActions(titles: List<String>): Pair<Int?, Int?> {
        fun find(words: List<String>) = titles.indexOfFirst { t -> words.any { t.trim().lowercase().startsWith(it) } }
            .takeIf { it >= 0 }
        return find(answerWords) to find(declineWords)
    }
}
