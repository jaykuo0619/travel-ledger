package com.archiekuo.travelledger.ui

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class ThemeMode(val label: String) { SYSTEM("跟隨系統"), LIGHT("淺色"), DARK("深色") }

/** In-app text size, applied on top of the system font size. */
enum class FontSize(val label: String, val scale: Float) { STANDARD("標準", 1f), LARGE("大", 1.12f), XLARGE("特大", 1.25f) }

data class AppSettings(
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val fontSize: FontSize = FontSize.STANDARD,
    /** Copy "memory" photos to the phone gallery automatically. */
    val saveMemoriesToGallery: Boolean = true,
    /** Shown on trips shared with companions. */
    val myName: String = "",
    /** Epoch day of the last backup (-1: never), for the "trip ended, back it up" reminder. */
    val lastBackupDay: Long = -1,
    /** Epoch day the reminder was last put off; it comes back when another trip ends. */
    val reminderDismissedDay: Long = -1,
    /** Calculator key height in dp, set by dragging the handle above the keypad. */
    val keypadKeyHeight: Float = KEY_HEIGHT_DEFAULT,
    /** After a file is imported, delete the file that was opened (never a backup: it may be the only copy). */
    val deleteImportedFile: Boolean = true,
)

object AppPrefs {
    private const val FILE = "settings"

    fun load(context: Context): AppSettings {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        return AppSettings(
            theme = p.getString("theme_mode", null)?.let { runCatching { ThemeMode.valueOf(it) }.getOrNull() } ?: ThemeMode.SYSTEM,
            fontSize = p.getString("font_size", null)?.let { runCatching { FontSize.valueOf(it) }.getOrNull() } ?: FontSize.STANDARD,
            saveMemoriesToGallery = p.getBoolean("save_memories", true),
            myName = p.getString("my_name", "") ?: "",
            lastBackupDay = p.getLong("last_backup_day", -1),
            reminderDismissedDay = p.getLong("reminder_dismissed_day", -1),
            keypadKeyHeight = p.getFloat("keypad_key_height", KEY_HEIGHT_DEFAULT).coerceIn(KEY_HEIGHT_MIN, KEY_HEIGHT_MAX),
            deleteImportedFile = p.getBoolean("delete_imported_file", true),
        )
    }

    fun save(context: Context, s: AppSettings) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putString("theme_mode", s.theme.name)
            .putString("font_size", s.fontSize.name)
            .putBoolean("save_memories", s.saveMemoriesToGallery)
            .putString("my_name", s.myName)
            .putLong("last_backup_day", s.lastBackupDay)
            .putLong("reminder_dismissed_day", s.reminderDismissedDay)
            .putFloat("keypad_key_height", s.keypadKeyHeight)
            .putBoolean("delete_imported_file", s.deleteImportedFile)
            .apply()
    }
}

/** Colors outside the Material scheme. */
@Immutable
data class LedgerColors(
    val dark: Boolean,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val field: Color,
    val hairline: Color,
    val textMuted: Color,
)

val LocalLedgerColors = staticCompositionLocalOf {
    LedgerColors(false, Color.Green, Color.Yellow, Color.Red, Color.LightGray, Color.LightGray, Color.Gray)
}

private val Indigo = Color(0xFF5B57F2)

private val LightScheme: ColorScheme = lightColorScheme(
    primary = Indigo,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFECEBFF),
    onPrimaryContainer = Color(0xFF2A2690),
    secondary = Color(0xFF6B6E80),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFEEEFF5),
    onSecondaryContainer = Color(0xFF2A2C38),
    background = Color(0xFFF5F6FA),
    onBackground = Color(0xFF15161C),
    surface = Color(0xFFF5F6FA),
    onSurface = Color(0xFF15161C),
    surfaceVariant = Color(0xFFEEEFF5),
    onSurfaceVariant = Color(0xFF6B6E80),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color.White,
    surfaceContainer = Color.White,
    surfaceContainerHigh = Color.White,
    surfaceContainerHighest = Color(0xFFEEEFF5),
    outline = Color(0xFFD9DBE5),
    outlineVariant = Color(0xFFE9EAF1),
    error = Color(0xFFE5484D),
    onError = Color.White,
    errorContainer = Color(0xFFFFE5E6),
    onErrorContainer = Color(0xFF8A1C20),
    inverseSurface = Color(0xFF22232B),
    inverseOnSurface = Color(0xFFF2F2F7),
)

private val DarkScheme: ColorScheme = darkColorScheme(
    primary = Color(0xFF8D8AFF),
    onPrimary = Color(0xFF16134A),
    primaryContainer = Color(0xFF2B2967),
    onPrimaryContainer = Color(0xFFE2E1FF),
    secondary = Color(0xFF9EA1B2),
    onSecondary = Color(0xFF15161C),
    secondaryContainer = Color(0xFF25262E),
    onSecondaryContainer = Color(0xFFE6E7EE),
    background = Color(0xFF0C0D11),
    onBackground = Color(0xFFEDEEF3),
    surface = Color(0xFF0C0D11),
    onSurface = Color(0xFFEDEEF3),
    surfaceVariant = Color(0xFF1F2027),
    onSurfaceVariant = Color(0xFF9A9DAD),
    surfaceContainerLowest = Color(0xFF16171C),
    surfaceContainerLow = Color(0xFF16171C),
    surfaceContainer = Color(0xFF16171C),
    surfaceContainerHigh = Color(0xFF1C1D23),
    surfaceContainerHighest = Color(0xFF24252D),
    outline = Color(0xFF34353F),
    outlineVariant = Color(0xFF24252D),
    error = Color(0xFFFF6B70),
    onError = Color(0xFF3A0B0D),
    errorContainer = Color(0xFF4A1518),
    onErrorContainer = Color(0xFFFFD9DA),
    inverseSurface = Color(0xFFEDEEF3),
    inverseOnSurface = Color(0xFF15161C),
)

private val LightExtra = LedgerColors(
    dark = false,
    success = Color(0xFF1DB37A),
    warning = Color(0xFFF2A10C),
    danger = Color(0xFFE5484D),
    field = Color(0xFFF3F4F8),
    hairline = Color(0xFFECEDF3),
    textMuted = Color(0xFF8E91A2),
)

private val DarkExtra = LedgerColors(
    dark = true,
    success = Color(0xFF34D399),
    warning = Color(0xFFFBBF24),
    danger = Color(0xFFFF6B70),
    field = Color(0xFF1F2027),
    hairline = Color(0xFF23242B),
    textMuted = Color(0xFF6E7182),
)

/** Tabular figures keep amounts aligned in lists. */
val Tnum = "tnum"

private val AppTypography = Typography().let { t ->
    t.copy(
        displayMedium = t.displayMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = Tnum, letterSpacing = (-0.5).sp),
        displaySmall = t.displaySmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = Tnum, letterSpacing = (-0.5).sp),
        headlineMedium = t.headlineMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = Tnum, letterSpacing = (-0.3).sp),
        headlineSmall = t.headlineSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp),
        titleLarge = t.titleLarge.copy(fontWeight = FontWeight.Bold, fontSize = 21.sp, lineHeight = 28.sp),
        titleMedium = t.titleMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 24.sp, fontFeatureSettings = Tnum),
        titleSmall = t.titleSmall.copy(fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp, fontFeatureSettings = Tnum),
        bodyLarge = t.bodyLarge.copy(fontSize = 16.sp, lineHeight = 23.sp, fontFeatureSettings = Tnum),
        bodyMedium = t.bodyMedium.copy(fontSize = 15.sp, lineHeight = 21.sp, fontFeatureSettings = Tnum),
        bodySmall = t.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp, fontFeatureSettings = Tnum),
        labelLarge = t.labelLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
        labelMedium = t.labelMedium.copy(fontWeight = FontWeight.Medium, fontSize = 13.sp),
    )
}

/** Small uppercase-ish caption used above fields and sections. */
val CaptionStyle = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.2.sp)

private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

@Composable
fun isDarkTheme(mode: ThemeMode): Boolean = when (mode) {
    ThemeMode.SYSTEM -> isSystemInDarkTheme()
    ThemeMode.LIGHT -> false
    ThemeMode.DARK -> true
}

@Composable
fun AppTheme(mode: ThemeMode = ThemeMode.SYSTEM, fontSize: FontSize = FontSize.STANDARD, content: @Composable () -> Unit) {
    val dark = isDarkTheme(mode)
    val density = LocalDensity.current
    CompositionLocalProvider(
        LocalLedgerColors provides if (dark) DarkExtra else LightExtra,
        LocalDensity provides Density(density.density, density.fontScale * fontSize.scale),
    ) {
        MaterialTheme(
            colorScheme = if (dark) DarkScheme else LightScheme,
            typography = AppTypography,
            shapes = AppShapes,
            content = content,
        )
    }
}

val ledger: LedgerColors
    @Composable get() = LocalLedgerColors.current
