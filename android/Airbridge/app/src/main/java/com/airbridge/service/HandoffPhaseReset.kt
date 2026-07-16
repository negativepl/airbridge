package com.airbridge.service

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow

/** How long a FAILED handoff phase stays visible before returning to IDLE. */
const val HANDOFF_FAILED_DISPLAY_MS = 5_000L

/**
 * Returns a FAILED handoff phase to IDLE after [delayMs], so the failure is
 * visible for a beat (Home error text) but never lingers as stale state.
 * Compare-and-set: a retry that moved the phase to IN_PROGRESS meanwhile is
 * left untouched. Unit-tested in HandoffPhaseResetTest.
 */
suspend fun autoClearFailedHandoff(
    phase: MutableStateFlow<HandoffPhase>,
    delayMs: Long = HANDOFF_FAILED_DISPLAY_MS,
) {
    delay(delayMs)
    phase.compareAndSet(HandoffPhase.FAILED, HandoffPhase.IDLE)
}
