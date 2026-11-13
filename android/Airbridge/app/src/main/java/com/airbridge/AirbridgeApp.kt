package com.airbridge

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.glance.appwidget.updateAll
import com.airbridge.widget.AirbridgeWidget
import com.airbridge.widget.ClipboardWidget
import com.airbridge.widget.ToolbarWidget
import com.airbridge.widget.WidgetPreviewWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class AirbridgeApp : Application() {

    override fun onCreate() {
        super.onCreate()
        publishWidgetPreviews()
        refreshWidgets()
    }

    /**
     * Android 15+ shows generated previews of the widgets in the picker. They
     * are published by a worker, only where missing and with backoff, as the
     * system rate-limits the calls.
     */
    private fun publishWidgetPreviews() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            WidgetPreviewWorker.enqueue(this)
        }
    }

    /**
     * Redraws the placed widgets. A widget with wallpaper colours and a fixed
     * light or dark theme holds a snapshot of the wallpaper's scheme, so this
     * brings it up to date after a wallpaper change.
     */
    private fun refreshWidgets() {
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            for (widget in listOf(ClipboardWidget(), AirbridgeWidget(), ToolbarWidget())) {
                runCatching { widget.updateAll(this@AirbridgeApp) }
                    .onFailure { Log.w("AirbridgeApp", "Widgets not refreshed", it) }
            }
        }
    }
}
