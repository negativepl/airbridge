package com.airbridge.service

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HandoffPhaseResetTest {

    @Test
    fun `failed phase auto-clears back to idle after the display window`() = runTest {
        val phase = MutableStateFlow(HandoffPhase.FAILED)
        launch { autoClearFailedHandoff(phase, delayMs = 5_000L) }

        advanceTimeBy(4_999L)
        runCurrent()
        assertEquals(HandoffPhase.FAILED, phase.value)

        advanceTimeBy(2L)
        runCurrent()
        assertEquals(HandoffPhase.IDLE, phase.value)
    }

    @Test
    fun `reset does not clobber a retry that started meanwhile`() = runTest {
        val phase = MutableStateFlow(HandoffPhase.FAILED)
        launch { autoClearFailedHandoff(phase, delayMs = 5_000L) }

        advanceTimeBy(1_000L)
        runCurrent()
        // The user retried before the reset fired.
        phase.value = HandoffPhase.IN_PROGRESS

        advanceTimeBy(10_000L)
        runCurrent()
        assertEquals(HandoffPhase.IN_PROGRESS, phase.value)
    }
}
