package com.airbridge.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.airbridge.R

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
