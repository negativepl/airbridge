package com.airbridge.ui.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.ExperimentalSerializationApi
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

    @Test fun popIfTopIgnoresASecondTap() {
        val stack: MutableList<NavKey> = mutableListOf(AppRoute.Tabs, AppRoute.Settings)
        stack.popIfTop(AppRoute.Settings)
        stack.popIfTop(AppRoute.Settings)
        assertEquals(listOf<NavKey>(AppRoute.Tabs), stack)
    }

    @Test fun popIfTopNeverEmptiesTheStack() {
        val stack: MutableList<NavKey> = mutableListOf(AppRoute.Tabs)
        stack.popIfTop(AppRoute.Tabs)
        assertEquals(listOf<NavKey>(AppRoute.Tabs), stack)
    }

    @Test fun pushIfAbsentIgnoresADuplicateOnTop() {
        val stack: MutableList<NavKey> = mutableListOf(AppRoute.Tabs)
        stack.pushIfAbsent(AppRoute.Settings)
        stack.pushIfAbsent(AppRoute.Settings)
        assertEquals(listOf<NavKey>(AppRoute.Tabs, AppRoute.Settings), stack)
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Test fun everyRouteIsSerializable() {
        val routes: List<AppRoute> = listOf(
            AppRoute.Onboarding, AppRoute.Tabs, AppRoute.Settings, AppRoute.About,
            AppRoute.QrScanner, AppRoute.PairingSuccess("Mac"),
        )
        routes.forEach { kotlinx.serialization.serializer(it::class, emptyList(), false) }
    }
}
