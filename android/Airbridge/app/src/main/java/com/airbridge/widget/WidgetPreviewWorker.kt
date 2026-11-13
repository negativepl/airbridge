package com.airbridge.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlin.reflect.KClass

/**
 * Publishes the widgets' generated previews (the widget picker on Android 15+)
 * for the widgets that do not have one yet. The system rate-limits these
 * calls, so a refused one is retried later with backoff instead of being
 * repeated on every start of the app.
 */
@RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
class WidgetPreviewWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val manager = GlanceAppWidgetManager(applicationContext)
        var rateLimited = false
        for (receiver in RECEIVERS) {
            if (hasPreview(receiver)) continue
            val result = runCatching { manager.setWidgetPreviews(receiver) }
                .onFailure { Log.w(TAG, "Preview not published: ${receiver.simpleName}", it) }
                .getOrNull()
            if (result == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_RATE_LIMITED) rateLimited = true
        }
        return if (rateLimited) Result.retry() else Result.success()
    }

    /** Whether the system already holds a generated home screen preview for [receiver]. */
    private fun hasPreview(receiver: KClass<out GlanceAppWidgetReceiver>): Boolean {
        val component = ComponentName(applicationContext, receiver.java)
        val info = AppWidgetManager.getInstance(applicationContext).installedProviders
            .firstOrNull { it.provider == component } ?: return false
        return info.generatedPreviewCategories and AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN != 0
    }

    companion object {
        private const val TAG = "WidgetPreviewWorker"
        private const val WORK_NAME = "widget_previews"

        private val RECEIVERS = listOf(
            ClipboardWidgetReceiver::class,
            AirbridgeWidgetReceiver::class,
            ToolbarWidgetReceiver::class,
        )

        /** Queues the work once; a run already waiting (e.g. on a rate-limit backoff) is kept. */
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<WidgetPreviewWorker>()
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request)
        }
    }
}
