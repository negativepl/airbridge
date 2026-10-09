package com.airbridge.ui

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.CardColors
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

// ──────────────────────────────────────────────
// Theme — natywny Material 3: dynamic color (Material You z tapety) na Androidzie 12+,
// fallback do natywnego baseline M3 na starszych. Bez custom palety.
// ──────────────────────────────────────────────
@Composable
fun AirbridgeTheme(
    themeMode: String = "system",
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> isSystemInDarkTheme()
    }

    val context = LocalContext.current
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialExpressiveTheme(
        colorScheme = colorScheme,
        // Stock Material 3 shape and type tokens; emphasis comes from the
        // *Emphasized styles of the Expressive type scale, never from a weight.
        shapes = Shapes(),
        typography = Typography(),
        content = content
    )
}

// Semantyczny kolor "sukcesu" (np. przyznane uprawnienia) — M3 nie ma go w ColorScheme.
val ColorScheme.success: Color
    get() = if (surface.luminance() < 0.5f) Color(0xFF81C784) else Color(0xFF2E7D32)

/**
 * Surfaces are layered the way Google's apps do it, in both modes: a tinted
 * page (surfaceContainer) with cards on the lowest container, which is white
 * in light and near-black in dark (Google One dark: black cards on a
 * dark-green page).
 */
val ColorScheme.pageBackground: Color
    get() = surfaceContainer

/** Card container that lifts off [pageBackground] in both modes. */
val ColorScheme.cardContainer: Color
    get() = surfaceContainerLowest

/** Navigation bar container: one container step off [pageBackground] so the dock reads as its own surface. */
val ColorScheme.dockContainer: Color
    get() = surfaceContainerHigh

/** Stock card colours with [cardContainer] as the container. */
@Composable
fun pageCardColors(): CardColors =
    CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.cardContainer)

/**
 * Top app bar colours that sit on [pageBackground], so the bar and the page
 * are one colour at rest and the bar steps up one container level once
 * content scrolls under it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun pageTopAppBarColors(tintWhenScrolled: Boolean = true): TopAppBarColors = TopAppBarDefaults.topAppBarColors(
    containerColor = MaterialTheme.colorScheme.pageBackground,
    scrolledContainerColor = if (tintWhenScrolled) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.pageBackground,
)

/**
 * Pure black or white for the tab titles: the tonal onSurface reads as
 * slightly coloured next to the page tint, which Marcin did not want there.
 */
val ColorScheme.tabTitleColor: Color
    get() = if (surface.luminance() < 0.5f) Color.White else Color.Black
