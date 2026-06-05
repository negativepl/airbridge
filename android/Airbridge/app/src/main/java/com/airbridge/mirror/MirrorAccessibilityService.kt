package com.airbridge.mirror

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Path
import android.os.Build
import android.view.accessibility.AccessibilityEvent

class MirrorAccessibilityService : AccessibilityService() {

    private val tapReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_TAP) return
            val xNorm = intent.getFloatExtra(EXTRA_X, -1f)
            val yNorm = intent.getFloatExtra(EXTRA_Y, -1f)
            if (xNorm !in 0f..1f || yNorm !in 0f..1f) return

            val metrics = resources.displayMetrics
            val x = metrics.widthPixels * xNorm
            val y = metrics.heightPixels * yNorm

            val path = Path().apply { moveTo(x, y) }
            // ~60 ms down→up so the system registers a real tap (1 ms was too short).
            val stroke = android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 60)
            val gesture = android.accessibilityservice.GestureDescription.Builder()
                .addStroke(stroke)
                .build()
            dispatchGesture(gesture, null, null)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val filter = IntentFilter(ACTION_TAP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(tapReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(tapReceiver, filter)
        }
    }

    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onDestroy() {
        runCatching { unregisterReceiver(tapReceiver) }
        super.onDestroy()
    }

    companion object {
        private const val ACTION_TAP = "com.airbridge.mirror.ACCESSIBILITY_TAP"
        private const val EXTRA_X = "x"
        private const val EXTRA_Y = "y"

        fun dispatchTap(context: Context, xNorm: Float, yNorm: Float) {
            val intent = Intent(ACTION_TAP)
                .setPackage(context.packageName)
                .putExtra(EXTRA_X, xNorm)
                .putExtra(EXTRA_Y, yNorm)
            context.sendBroadcast(intent)
        }
    }
}
