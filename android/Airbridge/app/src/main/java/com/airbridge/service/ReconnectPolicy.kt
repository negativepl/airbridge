package com.airbridge.service

/** Decision returned by [ReconnectPolicy] after a failed connection attempt. */
sealed class ReconnectDecision {
    /** Retry the same host after [delayMs]. */
    data class Retry(val delayMs: Long) : ReconnectDecision()

    /** Stop hammering the cached host; re-run discovery to find the peer again. */
    object Rediscover : ReconnectDecision()
}

/**
 * Pure decision logic for WebSocket reconnection: exponential backoff on the
 * cached host, falling back to re-discovery after [maxAttempts] direct retries.
 */
class ReconnectPolicy(
    private val maxAttempts: Int = 3,
    private val baseDelayMs: Long = 2000L,
    private val maxDelayMs: Long = 8000L,
) {
    private var attempts = 0

    fun onFailure(): ReconnectDecision {
        attempts++
        if (attempts >= maxAttempts) {
            return ReconnectDecision.Rediscover
        }
        val delay = baseDelayMs shl (attempts - 1)
        return ReconnectDecision.Retry(delay.coerceAtMost(maxDelayMs))
    }

    fun onSuccess() {
        attempts = 0
    }
}
