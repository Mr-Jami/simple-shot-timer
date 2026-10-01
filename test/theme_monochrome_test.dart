import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/theme/app_theme.dart';

/// The app is two-tone. Every colour role a stock Material widget can read
/// must be a grey, or the seed hue shows up in chips, badges and icons.
void main() {
  Map<String, Color> roles(ColorScheme s) => {
        'primary': s.primary,
        'onPrimary': s.onPrimary,
        'primaryContainer': s.primaryContainer,
        'onPrimaryContainer': s.onPrimaryContainer,
        'primaryFixed': s.primaryFixed,
        'primaryFixedDim': s.primaryFixedDim,
        'onPrimaryFixed': s.onPrimaryFixed,
        'onPrimaryFixedVariant': s.onPrimaryFixedVariant,
        'secondary': s.secondary,
        'onSecondary': s.onSecondary,
        'secondaryContainer': s.secondaryContainer,
        'onSecondaryContainer': s.onSecondaryContainer,
        'secondaryFixed': s.secondaryFixed,
        'secondaryFixedDim': s.secondaryFixedDim,
        'onSecondaryFixed': s.onSecondaryFixed,
        'onSecondaryFixedVariant': s.onSecondaryFixedVariant,
        'tertiary': s.tertiary,
        'onTertiary': s.onTertiary,
        'tertiaryContainer': s.tertiaryContainer,
        'onTertiaryContainer': s.onTertiaryContainer,
        'tertiaryFixed': s.tertiaryFixed,
        'tertiaryFixedDim': s.tertiaryFixedDim,
        'onTertiaryFixed': s.onTertiaryFixed,
        'onTertiaryFixedVariant': s.onTertiaryFixedVariant,
        'surface': s.surface,
        'onSurface': s.onSurface,
        'onSurfaceVariant': s.onSurfaceVariant,
        'outline': s.outline,
        'outlineVariant': s.outlineVariant,
        'surfaceDim': s.surfaceDim,
        'surfaceBright': s.surfaceBright,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
        'inverseSurface': s.inverseSurface,
        'onInverseSurface': s.onInverseSurface,
        'inversePrimary': s.inversePrimary,
        'surfaceTint': s.surfaceTint,
        'shadow': s.shadow,
        'scrim': s.scrim,
      };

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      test('$brightness highContrast=$highContrast has no hue outside error',
          () {
        final scheme = monochromeScheme(brightness, highContrast: highContrast);
        roles(scheme).forEach((name, color) {
          expect(
            HSLColor.fromColor(color).saturation,
            0,
            reason: '$name is not grey in $brightness hc=$highContrast',
          );
        });
      });
    }
  }

  test('high contrast has no grey secondary text', () {
    expect(
      monochromeScheme(Brightness.dark, highContrast: true).onSurfaceVariant,
      Colors.white,
    );
    expect(
      monochromeScheme(Brightness.light, highContrast: true).onSurfaceVariant,
      Colors.black,
    );
  });

  test('theme builds for every combination', () {
    for (final brightness in Brightness.values) {
      for (final highContrast in [false, true]) {
        expect(
          buildAppTheme(brightness, highContrast: highContrast).useMaterial3,
          isTrue,
        );
      }
    }
  });
}
