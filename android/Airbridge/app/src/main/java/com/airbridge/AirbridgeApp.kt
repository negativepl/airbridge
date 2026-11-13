package com.airbridge

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import com.airbridge.widget.AirbridgeWidgetReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AirbridgeApp : Application() {

    override fun onCreate() {
        super.onCreate()
        publishWidgetPreview()
    }

    /**
     * Android 15+ shows a generated preview of the widget in the picker instead
     * of a static image. The system rate-limits these calls, so a refused one
     * just keeps the preview it already has.
     */
    private fun publishWidgetPreview() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            runCatching {
                GlanceAppWidgetManager(this@AirbridgeApp).setWidgetPreviews(AirbridgeWidgetReceiver::class)
            }.onFailure { Log.w("AirbridgeApp", "Widget preview not published", it) }
        }
    }
}
