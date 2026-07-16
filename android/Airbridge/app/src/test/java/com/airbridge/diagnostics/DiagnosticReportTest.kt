package com.airbridge.diagnostics

import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DiagnosticReportTest {

    private fun makeInput(
        isConnected: Boolean = true,
        connectedDeviceName: String? = "MacBook Pro",
        connectedHost: String? = "192.168.1.10",
        logLines: List<String> = emptyList()
    ) = DiagnosticReport.Input(
        appVersion = "2.9.0-beta",
        versionCode = 20900,
        androidVersion = "16",
        sdkInt = 36,
        manufacturer = "samsung",
        model = "SM-F966B",
        isConnected = isConnected,
        connectedDeviceName = connectedDeviceName,
        connectedHost = connectedHost,
        logLines = logLines
    )

    // --- compose ---

    @Test
    fun `compose contains app and device versions`() {
        val report = DiagnosticReport.compose(makeInput())
        assertTrue(report.contains("2.9.0-beta"))
        assertTrue(report.contains("20900"))
        assertTrue(report.contains("Android 16 (API 36)"))
        assertTrue(report.contains("samsung SM-F966B"))
    }

    @Test
    fun `compose describes connected state with peer and host`() {
        val report = DiagnosticReport.compose(makeInput())
        assertTrue(report.contains("Connected: yes"))
        assertTrue(report.contains("MacBook Pro"))
        assertTrue(report.contains("192.168.1.10"))
    }

    @Test
    fun `compose describes disconnected state without peer fields`() {
        val report = DiagnosticReport.compose(
            makeInput(isConnected = false, connectedDeviceName = null, connectedHost = null)
        )
        assertTrue(report.contains("Connected: no"))
    }

    @Test
    fun `compose includes log lines in order`() {
        val report = DiagnosticReport.compose(makeInput(logLines = listOf("line A", "line B")))
        assertTrue(report.contains("line A\nline B"))
    }

    @Test
    fun `compose with no logs says so`() {
        val report = DiagnosticReport.compose(makeInput(logLines = emptyList()))
        assertTrue(report.contains("(no log entries)"))
    }

    // --- tail ---

    @Test
    fun `tail keeps short lists intact`() {
        assertEquals(listOf("a", "b"), DiagnosticReport.tail(listOf("a", "b")))
    }

    @Test
    fun `tail trims to the last max lines`() {
        val lines = (1..600).map { "line $it" }
        val tail = DiagnosticReport.tail(lines)
        assertEquals(500, tail.size)
        assertEquals("line 101", tail.first())
        assertEquals("line 600", tail.last())
    }

    // --- suggestedFileName ---

    @Test
    fun `suggested file name uses timestamp pattern`() {
        val cal = Calendar.getInstance(TimeZone.getDefault()).apply {
            set(2026, Calendar.JULY, 16, 9, 5, 0)
        }
        assertEquals(
            "airbridge-diagnostics-20260716-0905.txt",
            DiagnosticReport.suggestedFileName(Date(cal.timeInMillis))
        )
    }
}
