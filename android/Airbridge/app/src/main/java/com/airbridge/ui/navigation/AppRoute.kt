package com.airbridge.ui.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/** Back-stack keys. `Tabs` hosts the pager; everything else is pushed on top of it. */
sealed interface AppRoute : NavKey {
    @Serializable data object Onboarding : AppRoute
    @Serializable data object Tabs : AppRoute
    @Serializable data object Settings : AppRoute
    @Serializable data object About : AppRoute
    @Serializable data object QrScanner : AppRoute
    @Serializable data class PairingSuccess(val deviceName: String) : AppRoute
}

/** Replaces the whole stack, e.g. after pairing: `replaceAllWith(Tabs, PairingSuccess("Mac"))`. */
fun MutableList<NavKey>.replaceAllWith(vararg keys: NavKey) {
    clear()
    addAll(keys)
}
