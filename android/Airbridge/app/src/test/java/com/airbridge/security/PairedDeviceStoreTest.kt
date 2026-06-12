package com.airbridge.security

import org.junit.Assert.assertEquals
import org.junit.Test

class PairedDeviceStoreTest {
    @Test
    fun `round-trips cert fingerprint`() {
        val device = PairedDevice("Mac", "cGs=", "fp", 123L, certFingerprint = "ab12")
        assertEquals(device, pairedDeviceFromJson(device.toJson()))
    }

    @Test
    fun `legacy entry without cert fingerprint defaults to empty`() {
        val legacy = PairedDevice("Mac", "cGs=", "fp", 123L).toJson()
        legacy.remove("cert_fingerprint")
        assertEquals("", pairedDeviceFromJson(legacy).certFingerprint)
    }
}
