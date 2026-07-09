package com.airbridge.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReconnectGuardTest {

    @Test
    fun `guard is inactive by default`() {
        val guard = ReconnectGuard { 0L }
        assertFalse(guard.isActive)
    }

    @Test
    fun `guard is active within the armed window and expires after it`() {
        var now = 1_000L
        val guard = ReconnectGuard { now }
        guard.arm(15_000L)
        assertTrue(guard.isActive)
        now = 15_999L
        assertTrue(guard.isActive)
        now = 16_001L
        assertFalse(guard.isActive)
    }

    @Test
    fun `disarm deactivates immediately`() {
        var now = 1_000L
        val guard = ReconnectGuard { now }
        guard.arm(15_000L)
        guard.disarm()
        assertTrue(now == 1_000L)
        assertFalse(guard.isActive)
    }
}
