package com.airbridge.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbridge.R
import java.util.Locale

val CardShape = RoundedCornerShape(24.dp)

/** Locale-aware transfer speed label, e.g. "1.5 MB/s". Empty below 1 KB/s. */
fun formatTransferSpeed(bytesPerSecond: Long): String = when {
    bytesPerSecond > 1024 * 1024 ->
        String.format(Locale.getDefault(), "%.1f MB/s", bytesPerSecond / (1024.0 * 1024.0))
    bytesPerSecond > 1024 ->
        String.format(Locale.getDefault(), "%.0f KB/s", bytesPerSecond / 1024.0)
    else -> ""
}

@Composable
fun formatTimeAgo(timestamp: Long, now: Long): String {
    val diff = now - timestamp
    val minutes = (diff / 60_000).toInt()
    val hours = (diff / 3_600_000).toInt()
    return when {
        minutes < 1 -> stringResource(R.string.time_now)
        minutes < 60 -> stringResource(R.string.time_minutes, minutes)
        hours < 24 -> stringResource(R.string.time_hours, hours)
        else -> stringResource(R.string.time_days, hours / 24)
    }
}
