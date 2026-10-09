package com.airbridge.ui.navigation

import androidx.navigation3.runtime.NavKey
import org.junit.Assert.assertEquals
import org.junit.Test

class AppRouteTest {
    @Test fun replaceAllWithClearsThenPushesInOrder() {
        val stack: MutableList<NavKey> = mutableListOf(AppRoute.Onboarding, AppRoute.QrScanner)
        stack.replaceAllWith(AppRoute.Tabs, AppRoute.PairingSuccess("Mac"))
        assertEquals(listOf<NavKey>(AppRoute.Tabs, AppRoute.PairingSuccess("Mac")), stack)
    }

    @Test fun pairingSuccessCarriesTheName() {
        assertEquals("Studio", AppRoute.PairingSuccess("Studio").deviceName)
        assertEquals(AppRoute.PairingSuccess("A"), AppRoute.PairingSuccess("A"))
    }
}
