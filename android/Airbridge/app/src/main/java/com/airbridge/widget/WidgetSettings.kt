package com.airbridge.widget

import android.content.Context
import android.os.Build
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.ImageProvider
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.color.ColorProviders
import androidx.glance.layout.Box
import androidx.glance.layout.fillMaxSize
import androidx.glance.material3.ColorProviders
import androidx.glance.unit.ColorProvider
import com.airbridge.R

/**
 * Whether the Mac is connected, for the widgets: actions and the brand icon
 * are dimmed to Material's disabled emphasis while it is not.
 */
val LocalMacConnected = compositionLocalOf { true }

/** Material's emphasis for disabled content. */
const val DisabledAlpha = 0.38f

/** Where a widget takes its colours from. */
enum class WidgetColors { WALLPAPER, MONOCHROME }

/** Light, dark, or following the system. */
enum class WidgetThemeMode { SYSTEM, LIGHT, DARK }

/**
 * One placed widget's settings, kept in its Glance state (per widget) and
 * changed from WidgetSettingsActivity (the launcher's "Widget settings").
 */
data class WidgetSettings(
    val colors: WidgetColors = WidgetColors.WALLPAPER,
    val theme: WidgetThemeMode = WidgetThemeMode.SYSTEM,
    /** Opacity of the widget's background, 0..1; the buttons stay opaque. */
    val backgroundOpacity: Float = 1f,
) {
    fun writeTo(prefs: androidx.datastore.preferences.core.MutablePreferences) {
        prefs[KEY_COLORS] = colors.name
        prefs[KEY_THEME] = theme.name
        prefs[KEY_OPACITY] = backgroundOpacity
    }

    companion object {
        private val KEY_COLORS = stringPreferencesKey("colors")
        private val KEY_THEME = stringPreferencesKey("theme")
        private val KEY_OPACITY = floatPreferencesKey("background_opacity")

        fun from(prefs: Preferences?): WidgetSettings = WidgetSettings(
            colors = prefs?.get(KEY_COLORS)?.let { runCatching { WidgetColors.valueOf(it) }.getOrNull() } ?: WidgetColors.WALLPAPER,
            theme = prefs?.get(KEY_THEME)?.let { runCatching { WidgetThemeMode.valueOf(it) }.getOrNull() } ?: WidgetThemeMode.SYSTEM,
            backgroundOpacity = (prefs?.get(KEY_OPACITY) ?: 1f).coerceIn(0f, 1f),
        )
    }
}

/**
 * The widget's Material colours for [settings]. Wallpaper colours that follow
 * the system theme are Glance's own dynamic colours, read from the system's
 * resources, so they change with the wallpaper by themselves; every other
 * combination is built from a colour scheme.
 */
@Composable
fun WidgetTheme(context: Context, settings: WidgetSettings, content: @Composable () -> Unit) {
    val live = settings.colors == WidgetColors.WALLPAPER &&
        settings.theme == WidgetThemeMode.SYSTEM &&
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    if (live) {
        GlanceTheme(content = content)
        return
    }
    val (light, dark) = schemes(context, settings.colors)
    val colors: ColorProviders = when (settings.theme) {
        WidgetThemeMode.SYSTEM -> ColorProviders(light = light, dark = dark)
        WidgetThemeMode.LIGHT -> ColorProviders(light = light, dark = light)
        WidgetThemeMode.DARK -> ColorProviders(light = dark, dark = dark)
    }
    GlanceTheme(colors = colors, content = content)
}

/**
 * The widget's background in [color] at [opacity], in the launcher's rounded
 * shape. The colour is applied as a tint, so a dynamic colour stays dynamic.
 */
@Composable
fun WidgetBackground(color: ColorProvider, opacity: Float, content: @Composable () -> Unit) {
    val shape = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        GlanceModifier.cornerRadius(android.R.dimen.system_app_widget_background_radius)
    } else {
        GlanceModifier
    }
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(
                imageProvider = ImageProvider(R.drawable.widget_background),
                alpha = opacity,
                colorFilter = ColorFilter.tint(color),
            )
            .then(shape),
    ) {
        content()
    }
}

private fun schemes(context: Context, colors: WidgetColors): Pair<ColorScheme, ColorScheme> = when {
    colors == WidgetColors.MONOCHROME -> MonochromeLight to MonochromeDark
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> dynamicLightColorScheme(context) to dynamicDarkColorScheme(context)
    else -> lightColorScheme() to darkColorScheme()
}

/**
 * Greys only, like the black-and-white app icon and the system's monochrome
 * wallpaper style; the roles the widget uses follow M3's neutral tones.
 */
private val MonochromeLight = lightColorScheme(
    primary = Color(0xFF1F1F1F), onPrimary = Color.White,
    primaryContainer = Color(0xFFE3E3E3), onPrimaryContainer = Color(0xFF1F1F1F),
    secondary = Color(0xFF474747), onSecondary = Color.White,
    secondaryContainer = Color(0xFFE3E3E3), onSecondaryContainer = Color(0xFF1F1F1F),
    tertiary = Color(0xFF1F1F1F), onTertiary = Color.White,
    tertiaryContainer = Color(0xFFE3E3E3), onTertiaryContainer = Color(0xFF1F1F1F),
    background = Color(0xFFF9F9F9), onBackground = Color(0xFF1F1F1F),
    surface = Color(0xFFF9F9F9), onSurface = Color(0xFF1F1F1F),
    surfaceVariant = Color(0xFFE3E3E3), onSurfaceVariant = Color(0xFF474747),
    outline = Color(0xFF757575),
)

private val MonochromeDark = darkColorScheme(
    primary = Color(0xFFE3E3E3), onPrimary = Color(0xFF1F1F1F),
    primaryContainer = Color(0xFF474747), onPrimaryContainer = Color(0xFFE3E3E3),
    secondary = Color(0xFFC6C6C6), onSecondary = Color(0xFF1F1F1F),
    secondaryContainer = Color(0xFF474747), onSecondaryContainer = Color(0xFFE3E3E3),
    tertiary = Color(0xFFE3E3E3), onTertiary = Color(0xFF1F1F1F),
    tertiaryContainer = Color(0xFF474747), onTertiaryContainer = Color(0xFFE3E3E3),
    background = Color(0xFF131313), onBackground = Color(0xFFE3E3E3),
    surface = Color(0xFF131313), onSurface = Color(0xFFE3E3E3),
    surfaceVariant = Color(0xFF474747), onSurfaceVariant = Color(0xFFC6C6C6),
    outline = Color(0xFF919191),
)
