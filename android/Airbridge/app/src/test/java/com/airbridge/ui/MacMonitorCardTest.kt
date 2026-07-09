package com.airbridge.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Cross-device version parity comparison used by the Mac monitor card's
 * update hint — mismatch only when both sides reported a (non-empty) app
 * version and their base versions (ignoring a "-beta" suffix) differ.
 */
class MacMonitorCardTest {

    @Test fun mismatchWhenBaseVersionsDiffer() {
        assertEquals(true, isVersionMismatch("2.8.0-beta", "2.7.6-beta"))
    }

    @Test fun noMismatchWhenBaseVersionsEqualIgnoringSuffix() {
        assertEquals(false, isVersionMismatch("2.7.6-beta", "2.7.6"))
    }

    @Test fun noMismatchWhenEitherVersionIsEmpty() {
        assertEquals(false, isVersionMismatch("", "2.7.6-beta"))
        assertEquals(false, isVersionMismatch("2.7.6-beta", ""))
    }
}
