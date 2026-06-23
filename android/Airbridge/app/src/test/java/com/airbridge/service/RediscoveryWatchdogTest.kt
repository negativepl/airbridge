package com.airbridge.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RediscoveryWatchdogTest {

    @Test
    fun `never triggers while connected`() {
        val watchdog = RediscoveryWatchdog(intervalTicks = 2)

        repeat(10) { assertFalse(watchdog.onTick(isConnected = true)) }
    }

    @Test
    fun `triggers after the configured number of down ticks`() {
        val watchdog = RediscoveryWatchdog(intervalTicks = 2)

        assertFalse(watchdog.onTick(isConnected = false)) // 1st down tick
        assertTrue(watchdog.onTick(isConnected = false))  // 2nd down tick -> rediscover
    }

    @Test
    fun `keeps triggering every interval while it stays disconnected`() {
        val watchdog = RediscoveryWatchdog(intervalTicks = 2)

        assertFalse(watchdog.onTick(isConnected = false))
        assertTrue(watchdog.onTick(isConnected = false))  // fires
        assertFalse(watchdog.onTick(isConnected = false)) // counter reset, count again
        assertTrue(watchdog.onTick(isConnected = false))  // fires again
    }

    @Test
    fun `reconnecting resets the down counter`() {
        val watchdog = RediscoveryWatchdog(intervalTicks = 2)

        watchdog.onTick(isConnected = false)             // 1 down tick accrued
        assertFalse(watchdog.onTick(isConnected = true)) // reconnected -> reset
        // A single later down tick must not fire — the counter started over.
        assertFalse(watchdog.onTick(isConnected = false))
        assertTrue(watchdog.onTick(isConnected = false))
    }

    @Test
    fun `interval of one fires on the first down tick`() {
        val watchdog = RediscoveryWatchdog(intervalTicks = 1)

        assertTrue(watchdog.onTick(isConnected = false))
    }
}
