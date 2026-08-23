import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasz_budzet_domowy/app/theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme dla domyślnego wariantu — Material 3 + brightness', () {
      final theme = AppTheme.light(AppThemeVariant.spokojny);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme dla domyślnego wariantu — Material 3 + brightness', () {
      final theme = AppTheme.dark(AppThemeVariant.spokojny);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
    });

    test('każdy z 5 wariantów builduje się bez błędów (light + dark)', () {
      for (final v in AppThemeVariant.values) {
        expect(() => AppTheme.light(v), returnsNormally);
        expect(() => AppTheme.dark(v), returnsNormally);
      }
    });
  });

  group('CategoryPalette', () {
    test('has 12 colors', () {
      expect(CategoryPalette.palette.length, 12);
    });

    test('fromHex parses #RRGGBB correctly', () {
      final green = CategoryPalette.fromHex('#7AB87A');
      expect(green.toARGB32().toRadixString(16).toUpperCase(), 'FF7AB87A');
    });

    test('fromHex handles missing #', () {
      final green = CategoryPalette.fromHex('7AB87A');
      expect(green.toARGB32().toRadixString(16).toUpperCase(), 'FF7AB87A');
    });
  });
}
