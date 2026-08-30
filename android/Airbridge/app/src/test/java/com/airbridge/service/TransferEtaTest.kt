package com.airbridge.service

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The remaining-time estimate used integer division, so anything under a
 * second reported 0 — and 0 is what the UI treats as "no estimate", blanking
 * the countdown exactly as a transfer finishes. Same defect as the Mac's.
 */
class TransferEtaTest {

    @Test
    fun `half a second left rounds up to one`() {
        assertEquals(1, TransferEta.seconds(remainingBytes = 500_000, speedBps = 1_000_000))
    }

    @Test
    fun `a sliver left is still one second`() {
        assertEquals(1, TransferEta.seconds(remainingBytes = 1, speedBps = 1_000_000))
    }

    @Test
    fun `nothing left is zero`() {
        assertEquals(0, TransferEta.seconds(remainingBytes = 0, speedBps = 1_000_000))
    }

    @Test
    fun `whole seconds are not inflated`() {
        assertEquals(3, TransferEta.seconds(remainingBytes = 3_000_000, speedBps = 1_000_000))
    }

    @Test
    fun `unknown speed yields no estimate`() {
        assertEquals(0, TransferEta.seconds(remainingBytes = 1_000, speedBps = 0))
    }

    @Test
    fun `negative remaining is clamped`() {
        assertEquals(0, TransferEta.seconds(remainingBytes = -10, speedBps = 1_000))
    }
}
