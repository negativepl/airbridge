package com.airbridge.util

import java.util.Locale

/** Locale-aware transfer speed label, e.g. "1.5 MB/s". Empty below 1 KB/s. */
fun formatTransferSpeed(bytesPerSecond: Long): String = when {
    bytesPerSecond > 1024 * 1024 ->
        String.format(Locale.getDefault(), "%.1f MB/s", bytesPerSecond / (1024.0 * 1024.0))
    bytesPerSecond > 1024 ->
        String.format(Locale.getDefault(), "%.0f KB/s", bytesPerSecond / 1024.0)
    else -> ""
}
