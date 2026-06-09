package com.airbridge.service

import org.junit.Assert.assertEquals
import org.junit.Test

class ReconnectPolicyTest {

    @Test
    fun `first failure schedules retry with base delay`() {
        val policy = ReconnectPolicy(maxAttempts = 3, baseDelayMs = 2000L, maxDelayMs = 8000L)

        assertEquals(ReconnectDecision.Retry(2000L), policy.onFailure())
    }

    @Test
    fun `backoff doubles on each consecutive failure`() {
        val policy = ReconnectPolicy(maxAttempts = 10, baseDelayMs = 2000L, maxDelayMs = 8000L)

        assertEquals(ReconnectDecision.Retry(2000L), policy.onFailure())
        assertEquals(ReconnectDecision.Retry(4000L), policy.onFailure())
        assertEquals(ReconnectDecision.Retry(8000L), policy.onFailure())
    }

    @Test
    fun `backoff caps at max delay`() {
        val policy = ReconnectPolicy(maxAttempts = 10, baseDelayMs = 2000L, maxDelayMs = 8000L)

        policy.onFailure() // 2000
        policy.onFailure() // 4000
        policy.onFailure() // 8000
        assertEquals(ReconnectDecision.Retry(8000L), policy.onFailure()) // would be 16000, capped
    }

    @Test
    fun `requests rediscovery after max direct attempts`() {
        val policy = ReconnectPolicy(maxAttempts = 3, baseDelayMs = 2000L, maxDelayMs = 8000L)

        assertEquals(ReconnectDecision.Retry(2000L), policy.onFailure())
        assertEquals(ReconnectDecision.Retry(4000L), policy.onFailure())
        assertEquals(ReconnectDecision.Rediscover, policy.onFailure())
    }

    @Test
    fun `success resets backoff and attempt counter`() {
        val policy = ReconnectPolicy(maxAttempts = 3, baseDelayMs = 2000L, maxDelayMs = 8000L)

        policy.onFailure() // 2000
        policy.onFailure() // 4000
        policy.onSuccess()

        assertEquals(ReconnectDecision.Retry(2000L), policy.onFailure())
    }
}
