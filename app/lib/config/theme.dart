import 'package:flutter/material.dart';

/// Arqivon theme with glassmorphism-ready colour palettes.
class ArqivonTheme {
  ArqivonTheme._();

  // ── Colours ──────────────────────────────────────────────────────────

  static const Color primaryDark = Color(0xFF7C3AED); // Deep purple
  static const Color primaryLight = Color(0xFF8B5CF6);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color surfaceDark = Color(0xFF0F0F1A);
  static const Color surfaceCardDark = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFFF8F9FA);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color errorRed = Color(0xFFEF4444);
  static const Color successGreen = Color(0xFF10B981);

  // ── Dark theme ───────────────────────────────────────────────────────

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorSchemeSeed: primaryDark,
    scaffoldBackgroundColor: surfaceDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 1.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceCardDark.withOpacity(0.6),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceDark.withOpacity(0.9),
      indicatorColor: primaryDark.withOpacity(0.3),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryDark,
      foregroundColor: Colors.white,
    ),
  );

  // ── Light theme ──────────────────────────────────────────────────────

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorSchemeSeed: primaryLight,
    scaffoldBackgroundColor: surfaceLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        letterSpacing: 1.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceCardLight,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceCardLight,
      indicatorColor: primaryLight.withOpacity(0.2),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryLight,
      foregroundColor: Colors.white,
    ),
  );
}
