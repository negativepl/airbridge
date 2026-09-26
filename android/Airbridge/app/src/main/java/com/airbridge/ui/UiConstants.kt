package com.airbridge.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.airbridge.R

/** Relative time as a full phrase: "przed chwilą", "7 minut temu", "2 godziny temu", "3 dni temu". */
@Composable
fun formatTimeAgo(timestamp: Long, now: Long): String {
    val diff = now - timestamp
    val minutes = (diff / 60_000).toInt()
    val hours = (diff / 3_600_000).toInt()
    val days = hours / 24
    return when {
        minutes < 1 -> stringResource(R.string.time_ago_now)
        minutes < 60 -> pluralStringResource(R.plurals.time_ago_minutes, minutes, minutes)
        hours < 24 -> pluralStringResource(R.plurals.time_ago_hours, hours, hours)
        else -> pluralStringResource(R.plurals.time_ago_days, days, days)
    }
}
