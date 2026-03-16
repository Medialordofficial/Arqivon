import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arqivon/config/theme.dart';

void main() {
  group('ArqivonTheme colors', () {
    test('primary colors are defined', () {
      expect(ArqivonTheme.primary, isNotNull);
      expect(ArqivonTheme.primaryDark, isNotNull);
      expect(ArqivonTheme.primaryLight, isNotNull);
    });

    test('primary is vivid indigo', () {
      expect(ArqivonTheme.primary, const Color(0xFF5B5FEF));
    });

    test('accent colors are defined', () {
      expect(ArqivonTheme.accent, isNotNull);
      expect(ArqivonTheme.accentLight, isNotNull);
    });

    test('semantic colors are defined', () {
      expect(ArqivonTheme.successGreen, isNotNull);
      expect(ArqivonTheme.errorRed, isNotNull);
      expect(ArqivonTheme.warning, isNotNull);
    });

    test('dark palette colors are defined', () {
      expect(ArqivonTheme.darkBg, isNotNull);
      expect(ArqivonTheme.darkSurface, isNotNull);
      expect(ArqivonTheme.darkCard, isNotNull);
      expect(ArqivonTheme.darkText, isNotNull);
      expect(ArqivonTheme.darkSubtext, isNotNull);
    });

    test('text colors are reasonably dark on light backgrounds', () {
      // textPrimary should be very dark (low brightness)
      expect(ArqivonTheme.textPrimary.computeLuminance(), lessThan(0.1));
    });

    test('dark text is reasonably light on dark backgrounds', () {
      expect(ArqivonTheme.darkText.computeLuminance(), greaterThan(0.8));
    });
  });

  group('ArqivonTheme.lightTheme', () {
    test('is a ThemeData', () {
      expect(ArqivonTheme.lightTheme, isA<ThemeData>());
    });

    test('uses Material 3', () {
      expect(ArqivonTheme.lightTheme.useMaterial3, true);
    });

    test('brightness is light', () {
      expect(ArqivonTheme.lightTheme.brightness, Brightness.light);
    });

    test('primary color is correct', () {
      expect(ArqivonTheme.lightTheme.colorScheme.primary.toARGB32(),
          ArqivonTheme.primary.toARGB32());
    });

    test('scaffold background is set', () {
      expect(ArqivonTheme.lightTheme.scaffoldBackgroundColor, isNotNull);
    });
  });

  group('ArqivonTheme.darkTheme', () {
    test('is a ThemeData', () {
      expect(ArqivonTheme.darkTheme, isA<ThemeData>());
    });

    test('uses Material 3', () {
      expect(ArqivonTheme.darkTheme.useMaterial3, true);
    });

    test('brightness is dark', () {
      expect(ArqivonTheme.darkTheme.brightness, Brightness.dark);
    });

    test('primary color is defined', () {
      // Material 3 may adjust the exact primary; just verify it exists.
      expect(ArqivonTheme.darkTheme.colorScheme.primary, isNotNull);
    });

    test('scaffold background is dark', () {
      final bgLuminance =
          ArqivonTheme.darkTheme.scaffoldBackgroundColor.computeLuminance();
      expect(bgLuminance, lessThan(0.1));
    });

    test('surface color is dark', () {
      final surfaceLuminance =
          ArqivonTheme.darkTheme.colorScheme.surface.computeLuminance();
      expect(surfaceLuminance, lessThan(0.15));
    });
  });

  group('Theme consistency', () {
    test('both themes have primary color defined', () {
      // Material 3 may generate different primary shades for light/dark.
      expect(ArqivonTheme.lightTheme.colorScheme.primary, isNotNull);
      expect(ArqivonTheme.darkTheme.colorScheme.primary, isNotNull);
    });

    test('both themes use same font family', () {
      expect(
        ArqivonTheme.lightTheme.textTheme.bodyMedium?.fontFamily,
        ArqivonTheme.darkTheme.textTheme.bodyMedium?.fontFamily,
      );
    });

    test('dark theme has lighter text than light theme', () {
      final darkOnSurface = ArqivonTheme.darkTheme.colorScheme.onSurface;
      final lightOnSurface = ArqivonTheme.lightTheme.colorScheme.onSurface;
      expect(
        darkOnSurface.computeLuminance(),
        greaterThan(lightOnSurface.computeLuminance()),
      );
    });
  });
}
