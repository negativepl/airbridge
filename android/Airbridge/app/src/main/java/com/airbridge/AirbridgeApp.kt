package com.airbridge

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import com.airbridge.widget.AirbridgeWidgetReceiver
import com.airbridge.widget.ClipboardWidgetReceiver
import com.airbridge.widget.ToolbarWidgetReceiver
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
     * Android 15+ shows generated previews of the widgets in the picker instead
     * of a static image. The system rate-limits these calls, so a refused one
     * just keeps the preview it already has.
     */
    private fun publishWidgetPreview() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            val manager = GlanceAppWidgetManager(this@AirbridgeApp)
            for (receiver in listOf(ClipboardWidgetReceiver::class, AirbridgeWidgetReceiver::class, ToolbarWidgetReceiver::class)) {
                runCatching { manager.setWidgetPreviews(receiver) }
                    .onFailure { Log.w("AirbridgeApp", "Widget preview not published: ${receiver.simpleName}", it) }
            }
        }
    }
}
