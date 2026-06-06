package com.airbridge.ui

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

// ──────────────────────────────────────────────
// Amethyst on Graphite — premium dark, cool graphite
// surfaces with a vivid amethyst (purple) accent.
// ──────────────────────────────────────────────

// Primary — amethyst
private val Amethyst20 = Color(0xFF38215E)
private val Amethyst30 = Color(0xFF4B3580)
private val Amethyst40 = Color(0xFF6A4D9E)  // main primary (light scheme)
private val Amethyst80 = Color(0xFFCBB2F2)  // main primary (dark scheme)
private val Amethyst90 = Color(0xFFEADDFF)
private val Amethyst10 = Color(0xFF21104A)

// Secondary — muted lavender-grey
private val Lavender20 = Color(0xFF332E44)
private val Lavender30 = Color(0xFF494356)
private val Lavender40 = Color(0xFF615B73)
private val Lavender80 = Color(0xFFCAC1DD)
private val Lavender90 = Color(0xFFE7DEF8)
private val Lavender10 = Color(0xFF1D1A28)

// Tertiary — soft mauve/rose (warm partner to amethyst)
private val Mauve20 = Color(0xFF45213A)
private val Mauve30 = Color(0xFF5E3852)
private val Mauve40 = Color(0xFF7A5169)
private val Mauve80 = Color(0xFFE9B8D5)
private val Mauve90 = Color(0xFFFFD8EC)
private val Mauve10 = Color(0xFF2C0E25)

// Error
private val Error20 = Color(0xFF690005)
private val Error30 = Color(0xFF93000A)
private val Error40 = Color(0xFFBA1A1A)
private val Error80 = Color(0xFFFF8A80)   // clear coral-red (reads as destructive, not beige)
private val Error90 = Color(0xFFFFDAD6)

// ──────────────────────────────────────────────
// Light scheme — soft lavender-white with amethyst
// ──────────────────────────────────────────────
private val LightColorScheme = lightColorScheme(
    primary = Amethyst40,
    onPrimary = Color.White,
    primaryContainer = Amethyst90,
    onPrimaryContainer = Amethyst10,
    secondary = Lavender40,
    onSecondary = Color.White,
    secondaryContainer = Lavender90,
    onSecondaryContainer = Lavender10,
    tertiary = Mauve40,
    onTertiary = Color.White,
    tertiaryContainer = Mauve90,
    onTertiaryContainer = Mauve10,
    error = Error40,
    onError = Color.White,
    errorContainer = Error90,
    onErrorContainer = Error20,
    background = Color(0xFFFBF8FE),
    onBackground = Color(0xFF1B1A1F),
    surface = Color(0xFFFBF8FE),
    onSurface = Color(0xFF1B1A1F),
    surfaceVariant = Color(0xFFE6E0EC),
    onSurfaceVariant = Color(0xFF49454E),
    outline = Color(0xFF7A757F),
    outlineVariant = Color(0xFFCBC4D0),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF5F1FA),
    surfaceContainer = Color(0xFFEFEAF4),
    surfaceContainerHigh = Color(0xFFE9E4EF),
    surfaceContainerHighest = Color(0xFFE3DEE9)
)

// ──────────────────────────────────────────────
// Dark scheme — cool graphite with amethyst accent
// ──────────────────────────────────────────────
private val DarkColorScheme = darkColorScheme(
    primary = Amethyst80,
    onPrimary = Amethyst20,
    primaryContainer = Amethyst30,
    onPrimaryContainer = Amethyst90,
    secondary = Lavender80,
    onSecondary = Lavender20,
    secondaryContainer = Lavender30,
    onSecondaryContainer = Lavender90,
    tertiary = Mauve80,
    onTertiary = Mauve20,
    tertiaryContainer = Mauve30,
    onTertiaryContainer = Mauve90,
    error = Error80,
    onError = Error20,
    errorContainer = Error30,
    onErrorContainer = Error90,
    background = Color(0xFF141318),              // graphite, faint purple undertone
    onBackground = Color(0xFFE7E1EC),
    surface = Color(0xFF141318),
    onSurface = Color(0xFFE7E1EC),
    surfaceVariant = Color(0xFF48454E),
    onSurfaceVariant = Color(0xFFC9C3D2),
    outline = Color(0xFF938F99),
    outlineVariant = Color(0xFF48454E),
    surfaceContainerLowest = Color(0xFF0E0D12),
    surfaceContainerLow = Color(0xFF1C1B20),     // raised card
    surfaceContainer = Color(0xFF201F25),
    surfaceContainerHigh = Color(0xFF2B2930),
    surfaceContainerHighest = Color(0xFF36343B)
)

// ──────────────────────────────────────────────
// Typography
// ──────────────────────────────────────────────
private val AirbridgeTypography = Typography(
    displaySmall = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize = 36.sp,
        lineHeight = 44.sp,
    ),
    headlineLarge = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize = 32.sp,
        lineHeight = 40.sp,
    ),
    headlineMedium = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 36.sp,
    ),
    headlineSmall = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
    ),
    titleLarge = TextStyle(
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
    ),
    titleMedium = TextStyle(
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp,
    ),
    bodyLarge = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp,
    ),
    bodyMedium = TextStyle(
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.25.sp,
    ),
    labelLarge = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    labelMedium = TextStyle(
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
)

// ──────────────────────────────────────────────
// Shapes
// ──────────────────────────────────────────────
private val AirbridgeShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

// ──────────────────────────────────────────────
// Theme
// ──────────────────────────────────────────────
@Composable
fun AirbridgeTheme(
    themeMode: String = "system",
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        "light" -> false
        "dark" -> true
        else -> isSystemInDarkTheme()
    }

    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.surface.toArgb()
            window.navigationBarColor = colorScheme.surfaceContainer.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AirbridgeTypography,
        shapes = AirbridgeShapes,
        content = content
    )
}
