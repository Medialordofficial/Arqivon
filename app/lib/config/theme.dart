import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Arqivon — Clean White × Soft Purple design system.
class ArqivonTheme {
  ArqivonTheme._();

  // ── Core brand palette ────────────────────────────────────────────────

  /// Primary: soft purple.
  static const Color primary = Color(0xFF7C74A8);
  static const Color primaryDark = Color(0xFF5B5488);
  static const Color primaryLight = Color(0xFFEEECF5);

  /// Accent: brighter purple.
  static const Color accent = Color(0xFF9389C4);
  static const Color accentLight = Color(0xFFF3F1FA);

  /// Teal/green accent.
  static const Color teal = Color(0xFF6B9F5B);

  /// Success green.
  static const Color successGreen = Color(0xFF5DAE4E);

  /// Error red.
  static const Color errorRed = Color(0xFFD94E4E);

  /// Warning amber.
  static const Color warning = Color(0xFFE8943A);

  // ── Light surfaces ───────────────────────────────────────────────────

  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8F7FC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E1EF);
  static const Color divider = Color(0xFFF0EEF6);

  // ── Text ──────────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6E6E8A);

  // ── Dark palette ─────────────────────────────────────────────────────

  static const Color darkBg = Color(0xFF121218);
  static const Color darkSurface = Color(0xFF1C1C28);
  static const Color darkCard = Color(0xFF252535);
  static const Color darkText = Color(0xFFF0EEF6);
  static const Color darkSubtext = Color(0xFF9090A8);

  // ── Mode colors ───────────────────────────────────────────────────────
  static const Color modeGeneral = Color(0xFF7C74A8);
  static const Color modeTranslator = Color(0xFF9389C4);
  static const Color modeTutor = Color(0xFF6B9F5B);
  static const Color modeSupport = Color(0xFF8A7DB8);

  // ── Light theme ───────────────────────────────────────────────────────

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryDark,
      secondary: accent,
      onSecondary: Colors.white,
      tertiary: teal,
      surface: white,
      onSurface: textPrimary,
      surfaceContainerHighest: background,
      outline: borderColor,
      outlineVariant: divider,
      error: errorRed,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: background,
    fontFamily: 'NotoSans',
    appBarTheme: const AppBarTheme(
      backgroundColor: white,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x10000000),
      centerTitle: false,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.2,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      color: white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderColor),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: primaryLight,
      selectedColor: primary,
      labelStyle: const TextStyle(color: primaryDark, fontSize: 13),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: white,
      indicatorColor: primaryLight,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primary);
        }
        return const IconThemeData(color: textSecondary);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primary,
          );
        }
        return const TextStyle(fontSize: 12, color: textSecondary);
      }),
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      space: 1,
      thickness: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ── Dark theme ────────────────────────────────────────────────────────

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFADA4D4),
      onPrimary: darkBg,
      primaryContainer: Color(0xFF3A3558),
      onPrimaryContainer: Color(0xFFE0DCEF),
      secondary: Color(0xFFB5ADE0),
      onSecondary: darkBg,
      tertiary: Color(0xFF8BC17A),
      surface: darkCard,
      onSurface: darkText,
      surfaceContainerHighest: darkSurface,
      outline: Color(0xFF3A3850),
      error: Color(0xFFFF9B9B),
      onError: darkBg,
    ),
    scaffoldBackgroundColor: darkBg,
    fontFamily: 'NotoSans',
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurface,
      elevation: 0,
      iconTheme: IconThemeData(color: darkText),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: darkText,
        letterSpacing: -0.2,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2E2E42)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3850)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3850)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFADA4D4), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF9B9B), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF9B9B), width: 2),
      ),
      labelStyle: const TextStyle(color: darkSubtext),
      hintStyle: const TextStyle(color: darkSubtext),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFADA4D4),
        foregroundColor: darkBg,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFADA4D4),
        side: const BorderSide(color: Color(0xFFADA4D4)),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFADA4D4),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF3A3558),
      selectedColor: const Color(0xFFADA4D4),
      labelStyle: const TextStyle(color: Color(0xFFE0DCEF), fontSize: 13),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: const Color(0xFF3A3558),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFFADA4D4));
        }
        return const IconThemeData(color: darkSubtext);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF2E2E42),
      space: 1,
      thickness: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Color(0xFFADA4D4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkText,
      contentTextStyle: const TextStyle(color: darkBg),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
