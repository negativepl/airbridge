package com.airbridge.diagnostics

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import androidx.core.content.FileProvider
import com.airbridge.BuildConfig
import com.airbridge.service.AirbridgeService
import java.io.File

/**
 * Gathers live state, writes the diagnostic report to a cache file and
 * builds the share-sheet intent. Nothing leaves the device unless the user
 * completes the share flow.
 */
object DiagnosticReportExporter {

    /** Writes the report to `cacheDir/diagnostics/` and returns the file. */
    fun export(context: Context): File {
        val input = DiagnosticReport.Input(
            appVersion = BuildConfig.VERSION_NAME,
            versionCode = BuildConfig.VERSION_CODE,
            androidVersion = Build.VERSION.RELEASE,
            sdkInt = Build.VERSION.SDK_INT,
            manufacturer = Build.MANUFACTURER,
            model = Build.MODEL,
            isConnected = AirbridgeService.isConnected.value,
            connectedDeviceName = AirbridgeService.connectedDeviceName.value,
            connectedHost = AirbridgeService.connectedHost.value,
            logLines = DiagnosticReport.tail(readProcessLogs())
        )
        val dir = File(context.cacheDir, "diagnostics").apply { mkdirs() }
        // Stale reports are just cache; keep only the latest.
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, DiagnosticReport.suggestedFileName())
        file.writeText(DiagnosticReport.compose(input))
        return file
    }

    fun shareIntent(context: Context, file: File): Intent {
        val uri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider", file
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(send, null)
    }

    /** Recent logcat output of this process only (`logcat -d --pid`). */
    private fun readProcessLogs(): List<String> = runCatching {
        val process = Runtime.getRuntime().exec(
            arrayOf("logcat", "-d", "--pid", Process.myPid().toString())
        )
        process.inputStream.bufferedReader().use { it.readLines() }
    }.getOrDefault(emptyList())
}
