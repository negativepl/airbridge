package com.airbridge.ui.navigation

import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.IntOffset
import androidx.core.content.edit
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.airbridge.pairing.QrScannerScreen
import com.airbridge.ui.AboutScreen
import com.airbridge.ui.MainViewModel
import com.airbridge.ui.OnboardingScreen
import com.airbridge.ui.PairingSuccessScreen
import com.airbridge.ui.SettingsScreen
import com.airbridge.ui.TabsScreen

private const val ONBOARDING_DONE = "onboarding_completed"

/**
 * The app's screen graph. Pushed screens slide in a quarter of the width with a
 * fade on the theme's springs; predictive back is NavDisplay's default, which
 * follows the finger and can be cancelled.
 */
@Composable
fun AppNavHost(
    viewModel: MainViewModel,
    prefs: SharedPreferences,
    startAtOnboarding: Boolean,
    onThemeChanged: (String) -> Unit,
) {
    val backStack = rememberNavBackStack(if (startAtOnboarding) AppRoute.Onboarding else AppRoute.Tabs)
    val spatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
    val effects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()

    fun finishOnboarding() {
        prefs.edit { putBoolean(ONBOARDING_DONE, true) }
        backStack.replaceAllWith(AppRoute.Tabs)
    }

    NavDisplay(
        backStack = backStack,
        // Entries slide a quarter width while cross-fading, so the host must
        // carry the surface colour itself or the window background shows at the edges.
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface),
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        transitionSpec = {
            (slideInHorizontally(spatial) { it / 4 } + fadeIn(effects)) togetherWith
                (slideOutHorizontally(spatial) { -it / 4 } + fadeOut(effects))
        },
        popTransitionSpec = {
            (slideInHorizontally(spatial) { -it / 4 } + fadeIn(effects)) togetherWith
                (slideOutHorizontally(spatial) { it / 4 } + fadeOut(effects))
        },
        entryProvider = entryProvider {
            entry<AppRoute.Onboarding> {
                OnboardingScreen(
                    onFinished = { finishOnboarding() },
                    onScanQr = { backStack.add(AppRoute.QrScanner) },
                    onSkipPairing = { finishOnboarding() },
                )
            }
            entry<AppRoute.Tabs> {
                TabsScreen(
                    viewModel = viewModel,
                    onOpenSettings = { backStack.add(AppRoute.Settings) },
                    onScanQr = { backStack.add(AppRoute.QrScanner) },
                )
            }
            entry<AppRoute.Settings> {
                SettingsScreen(
                    prefs = prefs,
                    onThemeChanged = onThemeChanged,
                    onScanQr = { backStack.add(AppRoute.QrScanner) },
                    onBack = { backStack.removeLastOrNull() },
                    onOpenAbout = { backStack.add(AppRoute.About) },
                )
            }
            entry<AppRoute.About> {
                AboutScreen(onBack = { backStack.removeLastOrNull() })
            }
            entry<AppRoute.QrScanner> {
                QrScannerScreen(
                    onScanned = { payload ->
                        viewModel.handlePairingPayload(payload)
                        prefs.edit { putBoolean(ONBOARDING_DONE, true) }
                        backStack.replaceAllWith(AppRoute.Tabs, AppRoute.PairingSuccess("Mac"))
                    },
                    onDismiss = { backStack.removeLastOrNull() },
                )
            }
            entry<AppRoute.PairingSuccess> { key ->
                PairingSuccessScreen(
                    deviceName = key.deviceName,
                    onContinue = { backStack.removeLastOrNull() },
                )
            }
        },
    )
}
