package com.airbridge.stats

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.TimeUnit

data class StatCounters(
    val filesSent: Int = 0,
    val bytesSent: Long = 0,
    val filesReceived: Int = 0,
    val bytesReceived: Long = 0,
    val clipboardSyncs: Int = 0,
    val connectedSeconds: Long = 0,
    val sessions: Int = 0,
)

data class Stats(val today: StatCounters, val total: StatCounters)

/** Lokalny dzień (UTC-based epoch day) z timestampu ms. Czysta funkcja — testowalna. */
fun todayEpochDay(now: Long): Long = TimeUnit.MILLISECONDS.toDays(now)

fun formatBytes(bytes: Long): String = when {
    bytes >= 1024L * 1024 * 1024 -> String.format(java.util.Locale.US, "%.1f GB", bytes / (1024.0 * 1024 * 1024))
    bytes >= 1024L * 1024 -> String.format(java.util.Locale.US, "%.1f MB", bytes / (1024.0 * 1024))
    bytes >= 1024L -> String.format(java.util.Locale.US, "%.1f KB", bytes / 1024.0)
    else -> String.format(java.util.Locale.US, "%d B", bytes)
}

fun formatDuration(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    return if (h > 0) "${h}h ${m}m" else "${m}m"
}

/** Czysta logika liczników: gdy newDay, `today` startuje od zera; total zawsze kumuluje. */
fun applyDelta(stats: Stats, newDay: Boolean, delta: (StatCounters) -> StatCounters): Stats {
    val todayBase = if (newDay) StatCounters() else stats.today
    return Stats(today = delta(todayBase), total = delta(stats.total))
}

class StatsStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE)

    private val _stats = MutableStateFlow(load())
    val stats: StateFlow<Stats> = _stats.asStateFlow()

    private fun load(): Stats = Stats(today = read("today_"), total = read("total_"))

    private fun read(p: String) = StatCounters(
        filesSent = prefs.getInt("stat_${p}files_sent", 0),
        bytesSent = prefs.getLong("stat_${p}bytes_sent", 0),
        filesReceived = prefs.getInt("stat_${p}files_received", 0),
        bytesReceived = prefs.getLong("stat_${p}bytes_received", 0),
        clipboardSyncs = prefs.getInt("stat_${p}clipboard_syncs", 0),
        connectedSeconds = prefs.getLong("stat_${p}connected_seconds", 0),
        sessions = prefs.getInt("stat_${p}sessions", 0),
    )

    private fun write(e: SharedPreferences.Editor, p: String, c: StatCounters) {
        e.putInt("stat_${p}files_sent", c.filesSent)
        e.putLong("stat_${p}bytes_sent", c.bytesSent)
        e.putInt("stat_${p}files_received", c.filesReceived)
        e.putLong("stat_${p}bytes_received", c.bytesReceived)
        e.putInt("stat_${p}clipboard_syncs", c.clipboardSyncs)
        e.putLong("stat_${p}connected_seconds", c.connectedSeconds)
        e.putInt("stat_${p}sessions", c.sessions)
    }

    @Synchronized
    private fun mutate(delta: (StatCounters) -> StatCounters) {
        val today = todayEpochDay(System.currentTimeMillis())
        val newDay = prefs.contains("stat_day") && prefs.getLong("stat_day", today) != today
        val next = applyDelta(_stats.value, newDay, delta)
        val e = prefs.edit()
        write(e, "today_", next.today)
        write(e, "total_", next.total)
        e.putLong("stat_day", today)
        e.apply()
        _stats.value = next
    }

    fun recordFileSent(bytes: Long) = mutate { it.copy(filesSent = it.filesSent + 1, bytesSent = it.bytesSent + bytes) }
    fun recordFileReceived(bytes: Long) = mutate { it.copy(filesReceived = it.filesReceived + 1, bytesReceived = it.bytesReceived + bytes) }
    fun recordClipboardSync() = mutate { it.copy(clipboardSyncs = it.clipboardSyncs + 1) }
    fun recordSession() = mutate { it.copy(sessions = it.sessions + 1) }
    fun recordConnectedTime(seconds: Long) = mutate { it.copy(connectedSeconds = it.connectedSeconds + seconds) }
}
