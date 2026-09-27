import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App theme state holder for dynamic light/dark toggling.
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

/// Design Tokens & Theme Definitions
class AppTheme {
  // --- Discord Brand Palette ---
  static const Color discordPurple = Color(0xFF5865F2); // Primary Blurple
  static const Color discordDeepPurple = Color(0xFF4752C4); // Deep Blurple
  static const Color discordLightPurple = Color(0xFF7983F5); // Hover / Highlight Blurple
  static const Color discordGreen = Color(0xFF57F287); // Success Green
  static const Color discordYellow = Color(0xFFFEE75C); // Warning Yellow
  static const Color discordFuchsia = Color(0xFFEB459E); // Accent Fuchsia
  static const Color discordRed = Color(0xFFED4245); // Danger Red

  // --- Dark Mode Palette (Discord Dark / Midnight) ---
  static const Color darkScaffoldBg = Color(0xFF1E1F22); // Discord Main Dark
  static const Color darkMidnightBg = Color(0xFF111214); // Deepest Midnight
  static const Color darkSurface = Color(0xFF2B2D31); // Card Surface
  static const Color darkSurfaceVariant = Color(0xFF313338); // Slightly Elevated Surface
  static const Color darkTextPrimary = Color(0xFFF2F3F5); // Crisp Adaptive White
  static const Color darkTextSecondary = Color(0xFF949BA4); // Muted Text

  // --- Light Mode Palette (Adaptive Crisp White) ---
  static const Color lightScaffoldBg = Color(0xFFF2F3F5); // Modern Soft Off-White
  static const Color lightPureWhite = Color(0xFFFFFFFF); // Pure White Surface
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFE3E5E8);
  static const Color lightTextPrimary = Color(0xFF23272A); // Discord Dark Slate
  static const Color lightTextSecondary = Color(0xFF5C5E66); // Muted Dark Text

  /// Dark Theme Definition
  static ThemeData darkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkScaffoldBg,
      colorScheme: const ColorScheme.dark(
        primary: discordPurple,
        secondary: discordLightPurple,
        tertiary: discordFuchsia,
        surface: darkSurface,
        error: discordRed,
        onPrimary: Colors.white,
        onSurface: darkTextPrimary,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
        bodyColor: darkTextPrimary,
        displayColor: darkTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: darkTextPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: discordPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 6,
          shadowColor: discordPurple.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: discordPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    );
  }

  /// Adaptive Light Theme Definition (Crisp White + Glassmorphism)
  static ThemeData lightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightScaffoldBg,
      colorScheme: const ColorScheme.light(
        primary: discordPurple,
        secondary: discordDeepPurple,
        tertiary: discordFuchsia,
        surface: lightSurface,
        error: discordRed,
        onPrimary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ).apply(
        bodyColor: lightTextPrimary,
        displayColor: lightTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: lightTextPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: discordPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: discordPurple.withOpacity(0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: discordPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    );
  }
}
