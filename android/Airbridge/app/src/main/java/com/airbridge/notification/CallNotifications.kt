package com.airbridge.notification

import android.Manifest
import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.service.notification.StatusBarNotification
import android.util.Log
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.os.BundleCompat
import com.airbridge.service.AirbridgeService
import java.util.concurrent.ConcurrentHashMap

/**
 * Incoming calls, read from the phone app's own call notification. No telephony
 * permission is needed: the notification already carries who is calling and
 * the Answer / Decline buttons, and the notification listener can see it.
 *
 * Three shapes are understood:
 * - Notification.CallStyle of the incoming type (Android 12+): caller and the
 *   answer / decline intents are explicit extras;
 * - Notification.CallStyle of the ongoing type while the phone still rings:
 *   Samsung posts this one whenever its full-screen call UI is up (screen off,
 *   locked or folded), with only a hang-up button that, while ringing, only
 *   brings the call screen forward. Telling it from a call in progress needs
 *   the optional Phone permission (the SIMs' call state); answering and
 *   declining go through TelecomManager;
 * - an older "call" category notification: ringing is recognised by an action
 *   titled like Answer, and the buttons are matched by their titles.
 *
 * Answering from the Mac presses the same button on the phone (or answers
 * through Telecom), so the call itself stays on the phone: its speaker,
 * earpiece or connected headphones.
 */
object CallNotifications {
    private const val TAG = "CallNotifications"

    // Notification.EXTRA_CALL_TYPE & co. are API 31; the string keys work on
    // every version and read nothing on phones that never set them.
    private const val EXTRA_CALL_TYPE = "android.callType"
    private const val EXTRA_CALL_PERSON = "android.callPerson"
    private const val EXTRA_ANSWER_INTENT = "android.answerIntent"
    private const val EXTRA_DECLINE_INTENT = "android.declineIntent"
    private const val EXTRA_HANG_UP_INTENT = "android.hangUpIntent"
    private const val CALL_TYPE_INCOMING = 1
    private const val CALL_TYPE_ONGOING = 2

    /**
     * [answer] null with [answerViaTelecom] true: the notification has no answer
     * button, the call is answered through TelecomManager instead.
     * [declineViaTelecom]: the only button is Samsung's hang-up, which while the
     * phone rings just brings its call screen forward, so the call is rejected
     * through TelecomManager.
     */
    private class Ringing(
        val caller: String,
        val answer: PendingIntent?,
        val answerViaTelecom: Boolean,
        val decline: PendingIntent?,
        val declineViaTelecom: Boolean,
    ) {
        val canAnswer get() = answer != null || answerViaTelecom
        val canDecline get() = decline != null || declineViaTelecom
    }

    /** For Telecom and for sending the buttons' intents; set on the first posted notification. */
    @Volatile
    private var appContext: Context? = null

    /** sbn.key → the call it rings for. Written from the listener's binder thread, read from the socket's. */
    private val ringing = ConcurrentHashMap<String, Ringing>()

    /**
     * sbn.key → hang-up button of a call answered after ringing (null when the
     * notification has none). Kept so the Mac learns when the call ends and
     * can end it.
     */
    private val inProgress = ConcurrentHashMap<String, java.util.Optional<PendingIntent>>()

    /**
     * A notification was posted or updated. Returns true when it is a call
     * notification (ringing or not), so the caller does not also relay it as
     * an ordinary notification.
     */
    fun onPosted(context: Context, sbn: StatusBarNotification): Boolean {
        appContext = context.applicationContext
        val n = sbn.notification ?: return false
        val extras = n.extras
        val callType = if (extras.containsKey(EXTRA_CALL_TYPE)) extras.getInt(EXTRA_CALL_TYPE, -1) else null
        val actionTitles = n.actions?.map { it.title?.toString().orEmpty() }.orEmpty()
        val (answerIndex, declineIndex) = matchCallActions(actionTitles)
        val isCall = n.category == Notification.CATEGORY_CALL || callType != null
        if (!isCall) return false

        // Only asked for the ongoing CallStyle: the other shapes say it themselves.
        val phoneRinging = callType == CALL_TYPE_ONGOING && isPhoneRinging(context)
        val isRinging = isRingingCall(callType, answerIndex != null, phoneRinging)
        if (!isRinging) {
            if (ringing.remove(sbn.key) != null) {
                if (wasAnswered(context, callType)) {
                    // Answered (here or from the Mac): follow the call until it ends.
                    val hangUp = BundleCompat.getParcelable(extras, EXTRA_HANG_UP_INTENT, PendingIntent::class.java)
                    inProgress[sbn.key] = java.util.Optional.ofNullable(hangUp)
                    Log.i(TAG, "Call answered")
                    AirbridgeService.sendCallActive(sbn.key)
                } else {
                    Log.i(TAG, "Call stopped ringing")
                    AirbridgeService.sendCallEnded(sbn.key)
                }
            }
            return true
        }

        val caller = callerName(extras)
        val answer = BundleCompat.getParcelable(extras, EXTRA_ANSWER_INTENT, PendingIntent::class.java)
            ?: answerIndex?.let { n.actions[it].actionIntent }
        val decline = BundleCompat.getParcelable(extras, EXTRA_DECLINE_INTENT, PendingIntent::class.java)
            ?: declineIndex?.let { n.actions[it].actionIntent }
        val telecomAllowed = hasPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)
        val call = Ringing(
            caller = caller,
            answer = answer,
            answerViaTelecom = answer == null && telecomAllowed,
            decline = decline,
            declineViaTelecom = decline == null && telecomAllowed,
        )
        val previous = ringing.put(sbn.key, call)
        // The phone app re-posts the notification while it rings; tell the Mac
        // once per call, and again only if what it shows changed.
        if (previous == null || previous.caller != caller ||
            previous.canAnswer != call.canAnswer || previous.canDecline != call.canDecline
        ) {
            Log.i(TAG, "Incoming call (callType=$callType, answer=${call.canAnswer}, decline=${call.canDecline}, viaTelecom=${call.answerViaTelecom}/${call.declineViaTelecom})")
            AirbridgeService.sendCallIncoming(sbn.key, caller, canAnswer = call.canAnswer, canDecline = call.canDecline)
        }
        return true
    }

    /**
     * The phone's call state changed (ringing, answered, idle). The ongoing
     * CallStyle notification is not always re-posted when a ringing call is
     * answered, so the listener hands the current call notifications back here.
     */
    fun onCallStateChanged(context: Context, active: Array<StatusBarNotification>) {
        val keys = HashSet<String>()
        active.forEach { sbn ->
            if (onPosted(context, sbn)) keys += sbn.key
        }
        // A call notification gone without a removal callback: the call is over.
        (ringing.keys + inProgress.keys).filter { it !in keys }.forEach { end(it) }
    }

    fun onRemoved(key: String) = end(key)

    /** The call is over: declined, the caller hung up, or a call in progress ended. */
    private fun end(key: String) {
        val wasRinging = ringing.remove(key) != null
        val wasInProgress = inProgress.remove(key) != null
        if (wasRinging || wasInProgress) {
            Log.i(TAG, if (wasInProgress) "Call ended" else "Call stopped ringing")
            AirbridgeService.sendCallEnded(key)
        }
    }

    /**
     * A ringing call stopped ringing while its notification stays: answered,
     * unless the Phone permission shows no SIM off-hook (the call notification
     * lingers a moment after a missed or declined call).
     */
    private fun wasAnswered(context: Context, callType: Int?): Boolean =
        callStateOnAnySim(context, TelephonyManager.CALL_STATE_OFFHOOK)
            ?: (callType == CALL_TYPE_ONGOING || callType == null)

    /** The Mac pressed Answer or Decline, or End on a call in progress. False when that call or button is gone. */
    fun perform(callId: String, answer: Boolean): Boolean {
        val context = appContext ?: return false
        inProgress[callId]?.let { hangUp -> return if (answer) false else hangUp(context, hangUp.orElse(null)) }
        val call = ringing[callId] ?: return false
        if (answer && call.answer == null && call.answerViaTelecom) return answerViaTelecom(context)
        if (!answer && call.decline == null && call.declineViaTelecom) return declineViaTelecom(context)
        val intent = (if (answer) call.answer else call.decline) ?: return false
        return try {
            // The dialer's buttons often start its call activity: allow that
            // from the background, where the Mac's request arrives.
            intent.send(context, 0, null, null, null, null, backgroundStartOptions())
            true
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "Call action no longer valid", e)
            false
        }
    }

    private fun backgroundStartOptions(): Bundle? = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA -> ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS)
            .toBundle()
        // Android 14-15: ALLOWED is deprecated only in favour of ALLOW_ALWAYS,
        // which does not exist before Android 16; it is the one value here.
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
            .toBundle()
        else -> null
    }

    private fun answerViaTelecom(context: Context): Boolean {
        if (!hasPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)) return false
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return false
        return try {
            // Deprecated for companion apps in favour of an InCallService, which
            // only the default dialer can be; this is the one way left for an
            // app that is not the dialer to answer a ringing call.
            telecom.acceptRingingCall()
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Answer through Telecom refused", e)
            false
        }
    }

    /** Ends a call in progress: through Telecom when allowed, else the notification's hang-up button. */
    private fun hangUp(context: Context, button: PendingIntent?): Boolean {
        if (hasPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)) return declineViaTelecom(context)
        return try {
            button?.send(context, 0, null, null, null, null, backgroundStartOptions()) != null
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "Hang-up no longer valid", e)
            false
        }
    }

    private fun declineViaTelecom(context: Context): Boolean {
        if (!hasPermission(context, Manifest.permission.ANSWER_PHONE_CALLS)) return false
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return false
        return try {
            // Deprecated like acceptRingingCall, for the same reason; rejects
            // a ringing call, ends one in progress.
            telecom.endCall()
        } catch (e: SecurityException) {
            Log.w(TAG, "Decline through Telecom refused", e)
            false
        }
    }

    /**
     * Ringing on any SIM; false without the Phone permission. Android 12+ only:
     * before it the device-wide call state comes from the deprecated
     * TelephonyManager.getCallState, and the ongoing-while-ringing shape is a
     * One UI 8 behaviour anyway.
     */
    private fun isPhoneRinging(context: Context): Boolean =
        callStateOnAnySim(context, TelephonyManager.CALL_STATE_RINGING) ?: false

    /** Whether any SIM is in [state]; null when that cannot be read (no permission, before Android 12). */
    private fun callStateOnAnySim(context: Context, state: Int): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        if (!hasPermission(context, Manifest.permission.READ_PHONE_STATE)) return null
        val telephony = context.getSystemService(TelephonyManager::class.java) ?: return null
        return try {
            activeSubscriptionIds(context).any {
                telephony.createForSubscriptionId(it).callStateForSubscription == state
            }
        } catch (e: SecurityException) {
            null
        }
    }

    /** Active SIMs (the call can come in on either); needs READ_PHONE_STATE. */
    internal fun activeSubscriptionIds(context: Context): List<Int> = try {
        context.getSystemService(SubscriptionManager::class.java)
            ?.activeSubscriptionInfoList?.map { it.subscriptionId }.orEmpty()
    } catch (e: SecurityException) {
        emptyList()
    }

    private fun hasPermission(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** Calls still ringing, e.g. to announce to a Mac that just connected. */
    fun forEachRinging(block: (callId: String, caller: String, canAnswer: Boolean, canDecline: Boolean) -> Unit) {
        ringing.forEach { (key, call) -> block(key, call.caller, call.canAnswer, call.canDecline) }
    }

    fun clear() {
        ringing.clear()
        inProgress.clear()
    }

    private fun callerName(extras: Bundle): String {
        val person = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            BundleCompat.getParcelable(extras, EXTRA_CALL_PERSON, android.app.Person::class.java)?.name?.toString()
        } else null
        return person?.takeIf { it.isNotBlank() }
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.takeIf { it.isNotBlank() }
            ?: ""
    }

    /**
     * Ringing: a CallStyle notification of the incoming type, an ongoing one
     * while Telecom says the phone rings, or, without CallStyle, a call
     * notification that offers to answer.
     */
    internal fun isRingingCall(callType: Int?, hasAnswerAction: Boolean, phoneRinging: Boolean = false): Boolean =
        when (callType) {
            null -> hasAnswerAction
            CALL_TYPE_INCOMING -> true
            CALL_TYPE_ONGOING -> phoneRinging
            else -> false
        }

    private val answerWords = listOf("answer", "accept", "odbierz", "odebrać", "odebrac")
    private val declineWords = listOf("decline", "reject", "dismiss", "odrzuć", "odrzuc")

    /** Indexes of the Answer and Decline actions among the notification's action titles. */
    internal fun matchCallActions(titles: List<String>): Pair<Int?, Int?> {
        fun find(words: List<String>) = titles.indexOfFirst { t -> words.any { t.trim().lowercase().startsWith(it) } }
            .takeIf { it >= 0 }
        return find(answerWords) to find(declineWords)
    }
}
