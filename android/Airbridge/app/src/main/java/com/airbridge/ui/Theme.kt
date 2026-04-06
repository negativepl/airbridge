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
// Warm Beige palette — clean, modern, premium
// Base: soft cream with terracotta accent
// ──────────────────────────────────────────────

// Primary — warm terracotta/clay accent (stands out on beige)
private val Primary10 = Color(0xFF2C1510)
private val Primary20 = Color(0xFF4E2A20)
private val Primary30 = Color(0xFF723F30)
private val Primary40 = Color(0xFF8B5545)  // main primary light
private val Primary80 = Color(0xFFDDB5A5)  // main primary dark
private val Primary90 = Color(0xFFF2DDD4)
private val Primary95 = Color(0xFFFFF0EB)

// Secondary — muted warm rose
private val Secondary10 = Color(0xFF2B1517)
private val Secondary20 = Color(0xFF4A2C30)
private val Secondary30 = Color(0xFF654348)
private val Secondary40 = Color(0xFF7F5A60)
private val Secondary80 = Color(0xFFD5B8BD)
private val Secondary90 = Color(0xFFF2D8DC)

// Tertiary — sage green (natural complement to beige)
private val Tertiary10 = Color(0xFF121C14)
private val Tertiary20 = Color(0xFF263428)
private val Tertiary30 = Color(0xFF3C4D3F)
private val Tertiary40 = Color(0xFF546557)
private val Tertiary80 = Color(0xFFB5CBB8)
private val Tertiary90 = Color(0xFFD1E7D4)

// Neutral — warm sand
private val Neutral10 = Color(0xFF1D1B18)
private val Neutral20 = Color(0xFF322F2B)
private val Neutral30 = Color(0xFF4A4641)
private val Neutral50 = Color(0xFF7A756E)
private val Neutral60 = Color(0xFF948F87)
private val Neutral80 = Color(0xFFC9C4BB)
private val Neutral90 = Color(0xFFE6E1D8)

// Error
private val Error20 = Color(0xFF601410)
private val Error30 = Color(0xFF93000A)
private val Error40 = Color(0xFFBA1A1A)
private val Error80 = Color(0xFFFFB4AB)
private val Error90 = Color(0xFFFFDAD6)

// ──────────────────────────────────────────────
// Light scheme — clean cream/beige surfaces
// ──────────────────────────────────────────────
private val LightColorScheme = lightColorScheme(
    primary = Primary40,
    onPrimary = Color.White,
    primaryContainer = Primary90,
    onPrimaryContainer = Primary10,
    secondary = Secondary40,
    onSecondary = Color.White,
    secondaryContainer = Secondary90,
    onSecondaryContainer = Secondary10,
    tertiary = Tertiary40,
    onTertiary = Color.White,
    tertiaryContainer = Tertiary90,
    onTertiaryContainer = Tertiary10,
    error = Error40,
    onError = Color.White,
    errorContainer = Error90,
    onErrorContainer = Error20,
    background = Color(0xFFFFF9F5),              // warm off-white
    onBackground = Neutral10,
    surface = Color(0xFFFFF9F5),
    onSurface = Neutral10,
    surfaceVariant = Neutral90,
    onSurfaceVariant = Neutral30,
    outline = Neutral50,
    outlineVariant = Neutral80,
    surfaceContainerLowest = Color(0xFFFFFDFA),
    surfaceContainerLow = Color(0xFFFAF5EE),     // soft cream
    surfaceContainer = Color(0xFFF5F0E8),         // light beige
    surfaceContainerHigh = Color(0xFFEFEAE2),
    surfaceContainerHighest = Color(0xFFE9E4DC)
)

// ──────────────────────────────────────────────
// Dark scheme — warm dark with beige undertones
// ──────────────────────────────────────────────
private val DarkColorScheme = darkColorScheme(
    primary = Primary80,
    onPrimary = Primary20,
    primaryContainer = Primary30,
    onPrimaryContainer = Primary90,
    secondary = Secondary80,
    onSecondary = Secondary20,
    secondaryContainer = Secondary30,
    onSecondaryContainer = Secondary90,
    tertiary = Tertiary80,
    onTertiary = Tertiary20,
    tertiaryContainer = Tertiary30,
    onTertiaryContainer = Tertiary90,
    error = Error80,
    onError = Error20,
    errorContainer = Error30,
    onErrorContainer = Error90,
    background = Color(0xFF17140F),              // warm charcoal
    onBackground = Color(0xFFEAE4DA),
    surface = Color(0xFF17140F),
    onSurface = Color(0xFFEAE4DA),
    surfaceVariant = Neutral30,
    onSurfaceVariant = Neutral80,
    outline = Neutral60,
    outlineVariant = Neutral30,
    surfaceContainerLowest = Color(0xFF110F0A),
    surfaceContainerLow = Color(0xFF1F1C17),
    surfaceContainer = Color(0xFF24211B),
    surfaceContainerHigh = Color(0xFF2F2C25),
    surfaceContainerHighest = Color(0xFF3A3730)
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
