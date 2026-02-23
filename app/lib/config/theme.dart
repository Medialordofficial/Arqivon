import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Arqivon — Vivid Indigo × White design system.
class ArqivonTheme {
  ArqivonTheme._();

  // ── Core brand palette ────────────────────────────────────────────────

  /// Primary: vivid indigo.
  static const Color primary = Color(0xFF5B5FEF);
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color primaryLight = Color(0xFFEEF2FF);

  /// Accent: bright sky blue.
  static const Color accent = Color(0xFF0EA5E9);
  static const Color accentLight = Color(0xFFE0F2FE);

  /// Fresh teal.
  static const Color teal = Color(0xFF14B8A6);

  /// Success green.
  static const Color successGreen = Color(0xFF10B981);

  /// Error red.
  static const Color errorRed = Color(0xFFEF4444);

  /// Warning amber.
  static const Color warning = Color(0xFFF59E0B);

  // ── Light surfaces ───────────────────────────────────────────────────

  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);

  // ── Text ──────────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  // ── Dark palette ─────────────────────────────────────────────────────

  static const Color darkBg = Color(0xFF0B0F1A);
  static const Color darkSurface = Color(0xFF131929);
  static const Color darkCard = Color(0xFF1E2640);
  static const Color darkText = Color(0xFFF1F5F9);
  static const Color darkSubtext = Color(0xFF94A3B8);

  // ── Mode colors ───────────────────────────────────────────────────────
  static const Color modeGeneral = Color(0xFF5B5FEF);
  static const Color modeTranslator = Color(0xFF0EA5E9);
  static const Color modeTutor = Color(0xFF10B981);
  static const Color modeSupport = Color(0xFFF59E0B);

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
    fontFamily: 'Roboto',
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
      primary: Color(0xFF818CF8),
      onPrimary: darkBg,
      primaryContainer: Color(0xFF312E81),
      onPrimaryContainer: Color(0xFFC7D2FE),
      secondary: Color(0xFF38BDF8),
      onSecondary: darkBg,
      tertiary: Color(0xFF2DD4BF),
      surface: darkCard,
      onSurface: darkText,
      surfaceContainerHighest: darkSurface,
      outline: Color(0xFF334155),
      error: Color(0xFFFCA5A5),
      onError: darkBg,
    ),
    scaffoldBackgroundColor: darkBg,
    fontFamily: 'Roboto',
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
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: const Color(0xFF312E81),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF818CF8));
        }
        return const IconThemeData(color: darkSubtext);
      }),
    ),
  );
}
