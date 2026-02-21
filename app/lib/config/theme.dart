import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Arqivo — Coffee Brown + Pure White design system.
class ArqivonTheme {
  ArqivonTheme._();

  // ── Palette ───────────────────────────────────────────────────────────

  /// Rich espresso — primary brand colour.
  static const Color espresso = Color(0xFF3E1F0D);

  /// Classic coffee brown — secondary.
  static const Color coffeeBrown = Color(0xFF6F4E37);

  /// Warm caramel — interactive accent (buttons, links, focus).
  static const Color caramel = Color(0xFFB07840);

  /// Latte — light warm surface tint.
  static const Color latte = Color(0xFFF5EDE3);

  /// Cream — card / input background.
  static const Color cream = Color(0xFFFAF7F4);

  /// Pure white background.
  static const Color white = Color(0xFFFFFFFF);

  /// Near-black warm text.
  static const Color inkBrown = Color(0xFF1C0A00);

  /// Secondary muted text.
  static const Color warmGrey = Color(0xFF8A6E5E);

  /// Error.
  static const Color errorRed = Color(0xFFD94040);

  /// Success.
  static const Color successGreen = Color(0xFF3A8A5C);

  // ── Dark palette ─────────────────────────────────────────────────────

  static const Color darkBg = Color(0xFF140B06);
  static const Color darkSurface = Color(0xFF1F1109);
  static const Color darkCard = Color(0xFF2C160B);
  static const Color darkText = Color(0xFFF5EDE3);
  static const Color darkSubtext = Color(0xFFB09080);

  // ── Light theme (default — pure white + coffee brown) ─────────────────

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: espresso,
      onPrimary: Colors.white,
      primaryContainer: latte,
      onPrimaryContainer: espresso,
      secondary: coffeeBrown,
      onSecondary: Colors.white,
      tertiary: caramel,
      surface: white,
      onSurface: inkBrown,
      surfaceContainerHighest: cream,
      outline: const Color(0xFFD9C8BC),
      outlineVariant: const Color(0xFFEDE0D6),
      error: errorRed,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: white,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: white,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x14000000),
      centerTitle: false,
      iconTheme: IconThemeData(color: espresso),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: inkBrown,
        letterSpacing: 0.1,
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
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Color(0xFFE8D9CF), width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cream,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDD0C8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDD0C8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: caramel, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorRed, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: warmGrey, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: caramel, fontSize: 12),
      prefixIconColor: warmGrey,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: espresso,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: espresso,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: espresso,
        minimumSize: const Size(double.infinity, 50),
        side: const BorderSide(color: Color(0xFFD9C8BC), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: caramel,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cream,
      selectedColor: latte,
      labelStyle: const TextStyle(fontSize: 12, color: inkBrown),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: Color(0xFFDDD0C8)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFEDE0D6),
      thickness: 1,
      space: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: white,
      indicatorColor: latte,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: espresso);
        }
        return const IconThemeData(color: warmGrey);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: espresso,
          );
        }
        return const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: warmGrey,
        );
      }),
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x14000000),
      elevation: 2,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: espresso,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: inkBrown,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: coffeeBrown,
    ),
  );

  // ── Dark theme ────────────────────────────────────────────────────────

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: caramel,
      onPrimary: Colors.white,
      primaryContainer: darkCard,
      onPrimaryContainer: latte,
      secondary: coffeeBrown,
      onSecondary: Colors.white,
      surface: darkBg,
      onSurface: darkText,
      surfaceContainerHighest: darkSurface,
      outline: Color(0xFF4A3020),
      outlineVariant: Color(0xFF2D1A10),
      error: errorRed,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: darkBg,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: latte),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: darkText,
        letterSpacing: 0.1,
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
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF3A2010), width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4A3020)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4A3020)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: caramel, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: darkSubtext, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: caramel, fontSize: 12),
      prefixIconColor: darkSubtext,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: caramel,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: latte,
        minimumSize: const Size(double.infinity, 50),
        side: const BorderSide(color: Color(0xFF4A3020), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: caramel,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF3A2010),
      thickness: 1,
      space: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: darkCard,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: caramel);
        }
        return const IconThemeData(color: darkSubtext);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: caramel,
          );
        }
        return const TextStyle(
          fontSize: 11,
          color: darkSubtext,
        );
      }),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: caramel,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkCard,
      contentTextStyle: const TextStyle(color: darkText, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: caramel,
    ),
  );
}
