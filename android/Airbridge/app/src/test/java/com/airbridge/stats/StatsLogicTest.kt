package com.airbridge.stats

import org.junit.Assert.assertEquals
import org.junit.Test

class StatsLogicTest {
    @Test fun formatBytes_scalesUnits() {
        assertEquals("512 B", formatBytes(512))
        assertEquals("1.5 KB", formatBytes(1536))
        assertEquals("2.0 MB", formatBytes(2L * 1024 * 1024))
        assertEquals("1.0 GB", formatBytes(1024L * 1024 * 1024))
    }

    @Test fun formatDuration_hoursAndMinutes() {
        assertEquals("0m", formatDuration(30))
        assertEquals("5m", formatDuration(5 * 60))
        assertEquals("4h 12m", formatDuration(4 * 3600 + 12 * 60))
    }

    @Test fun applyDelta_accumulatesWhenSameDay() {
        val base = Stats(StatCounters(), StatCounters())
        val r = applyDelta(base, newDay = false) {
            it.copy(filesSent = it.filesSent + 1, bytesSent = it.bytesSent + 1000)
        }
        assertEquals(1, r.today.filesSent)
        assertEquals(1000, r.today.bytesSent)
        assertEquals(1, r.total.filesSent)
        val r2 = applyDelta(r, newDay = false) { it.copy(filesSent = it.filesSent + 1) }
        assertEquals(2, r2.today.filesSent)
        assertEquals(2, r2.total.filesSent)
    }

    @Test fun applyDelta_resetsTodayOnNewDayKeepsTotal() {
        val base = Stats(StatCounters(filesSent = 5), StatCounters(filesSent = 5))
        val r = applyDelta(base, newDay = true) { it.copy(filesSent = it.filesSent + 1) }
        assertEquals(1, r.today.filesSent)   // today wyzerowane, potem +1
        assertEquals(6, r.total.filesSent)   // total zachowany
    }
}
