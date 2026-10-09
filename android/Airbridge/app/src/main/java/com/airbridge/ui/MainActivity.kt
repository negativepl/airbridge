package com.airbridge.ui

import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.airbridge.service.AirbridgeService
import com.airbridge.ui.navigation.AppNavHost

private const val STARTUP_HOLD_MS = 4_000L

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Hold the system splash until the Mac is connected and has reported
        // its info (wallpaper, stats), so Home composes straight into its final
        // layout. Bounded: if nothing arrives within STARTUP_HOLD_MS, or there is
        // nothing to connect to, the splash goes away anyway.
        val splash = installSplashScreen()
        val startedAt = SystemClock.uptimeMillis()
        val expectsConnection = savedInstanceState == null &&
            getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE).getBoolean("auto_connect", true) &&
            com.airbridge.security.PairedDeviceStore(this).getAll().isNotEmpty()
        splash.setKeepOnScreenCondition {
            expectsConnection &&
                !(AirbridgeService.isConnected.value && AirbridgeService.macInfo.value != null) &&
                SystemClock.uptimeMillis() - startedAt < STARTUP_HOLD_MS
        }
        // Exit: the icon grows and fades, uncovering the home screen underneath.
        splash.setOnExitAnimationListener { view ->
            val icon = view.iconView
            val duration = 380L
            icon.animate()
                .scaleX(6f).scaleY(6f).alpha(0f)
                .setInterpolator(android.view.animation.PathInterpolator(0.2f, 0f, 0f, 1f))
                .setDuration(duration)
                .start()
            view.view.animate()
                .alpha(0f)
                .setStartDelay(duration / 3)
                .setDuration(duration * 2 / 3)
                .withEndAction { view.remove() }
                .start()
        }
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        viewModel.startService()

        setContent {
            val prefs = remember { getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE) }
            val startAtOnboarding = remember { !prefs.getBoolean("onboarding_completed", false) }
            var themeMode by remember { mutableStateOf(prefs.getString("theme_mode", "dark") ?: "dark") }
            AirbridgeTheme(themeMode = themeMode) {
                AppNavHost(
                    viewModel = viewModel,
                    prefs = prefs,
                    startAtOnboarding = startAtOnboarding,
                    onThemeChanged = { themeMode = it },
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Returning to the app is the user's cue that they expect a connection.
        // If a background discovery had gone stale (network switched while we
        // were away), this recovers it at once; the service ignores it when
        // already connected.
        viewModel.rediscover()
    }
}
