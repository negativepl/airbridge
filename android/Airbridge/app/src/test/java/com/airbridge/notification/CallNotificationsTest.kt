package com.airbridge.notification

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallNotificationsTest {
    @Test fun callStyleIncomingRings() = assertTrue(CallNotifications.isRingingCall(callType = 1, hasAnswerAction = false))
    @Test fun callStyleOngoingDoesNotRing() = assertFalse(CallNotifications.isRingingCall(callType = 2, hasAnswerAction = true))
    @Test fun callStyleScreeningDoesNotRing() = assertFalse(CallNotifications.isRingingCall(callType = 3, hasAnswerAction = false))
    @Test fun legacyRingsWithAnswerAction() = assertTrue(CallNotifications.isRingingCall(callType = null, hasAnswerAction = true))
    @Test fun legacyOngoingHasNoAnswer() = assertFalse(CallNotifications.isRingingCall(callType = null, hasAnswerAction = false))

    @Test fun polishSamsungActions() =
        assertEquals(1 to 0, CallNotifications.matchCallActions(listOf("Odrzuć", "Odbierz")))

    @Test fun englishActions() =
        assertEquals(0 to 1, CallNotifications.matchCallActions(listOf("Answer", "Decline")))

    @Test fun ongoingCallActions() =
        assertEquals(null to null, CallNotifications.matchCallActions(listOf("Speaker", "Hang up")))
}
