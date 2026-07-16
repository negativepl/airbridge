package com.airbridge.diagnostics

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Builds the one-file diagnostic report the user can attach to a bug report.
 * Pure input-to-string composition, so it is unit testable; live state is
 * gathered by [DiagnosticReportExporter]. The report never includes keys or
 * tokens — local IP addresses are fine.
 */
object DiagnosticReport {

    const val MAX_LOG_LINES = 500

    data class Input(
        val appVersion: String,
        val versionCode: Int,
        val androidVersion: String,
        val sdkInt: Int,
        val manufacturer: String,
        val model: String,
        val isConnected: Boolean,
        val connectedDeviceName: String?,
        val connectedHost: String?,
        val logLines: List<String>
    )

    fun compose(input: Input, generatedAt: Date = Date()): String {
        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).format(generatedAt)
        val lines = mutableListOf<String>()
        lines += "AirBridge diagnostic report (Android)"
        lines += "Generated: $timestamp"
        lines += ""
        lines += "== App =="
        lines += "App version: ${input.appVersion} (${input.versionCode})"
        lines += "Android ${input.androidVersion} (API ${input.sdkInt})"
        lines += "Device: ${input.manufacturer} ${input.model}"
        lines += ""
        lines += "== Connection =="
        lines += "Connected: ${if (input.isConnected) "yes" else "no"}"
        input.connectedDeviceName?.let { lines += "Peer: $it" }
        input.connectedHost?.let { lines += "Host: $it" }
        lines += ""
        lines += "== Process logs (last $MAX_LOG_LINES lines) =="
        if (input.logLines.isEmpty()) {
            lines += "(no log entries)"
        } else {
            lines += input.logLines
        }
        lines += ""
        return lines.joinToString("\n")
    }

    fun tail(lines: List<String>, max: Int = MAX_LOG_LINES): List<String> = lines.takeLast(max)

    fun suggestedFileName(time: Date = Date()): String {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(time)
        return "airbridge-diagnostics-$stamp.txt"
    }
}
