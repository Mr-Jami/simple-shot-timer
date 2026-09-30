import 'package:flutter/material.dart';

/// Builds the app's [ThemeData] for one brightness.
///
/// The palette is true monochrome: a pure black/white headline pair, neutral
/// grey container variants and no hue anywhere except the functional error
/// red. Every Material colour role a stock widget can pick up is overridden
/// in [monochromeScheme]; `test/theme_monochrome_test.dart` guards that no
/// seed hue leaks back in.
ThemeData buildAppTheme(Brightness brightness, {required bool highContrast}) {
  final scheme = monochromeScheme(brightness, highContrast: highContrast);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Kill the M3 surface-tint bloom globally so elevated surfaces (dialogs,
    // bottom sheets, menus) stay neutral grey instead of picking up a hue.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outline,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      // A visible edge so menus read as a surface on a black background.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
    // Selected choice chips invert (ink pill, paper label), the same
    // treatment the START button uses, instead of M3's tinted container.
    chipTheme: ChipThemeData(
      selectedColor: scheme.onSurface,
      checkmarkColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.outline,
          width: highContrast ? 2 : 1,
        ),
      ),
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.surface
              : scheme.onSurface,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    // Bottom tabs: the selected icon sits in an inverted pill, the same
    // treatment as a selected chip and the START button.
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.onSurface,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.surface
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    textTheme: const TextTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
  );
}

/// True-monochrome [ColorScheme]. Every role is a grey (saturation 0) except
/// the error roles, which keep their conventional red.
///
/// [highContrast] removes the grey-on-black secondary text, turns outlines
/// pure white/black and lifts the container fills so tiles and chips still
/// separate from the background at maximum contrast.
ColorScheme monochromeScheme(
  Brightness brightness, {
  required bool highContrast,
}) {
  // Use a neutral grey seed so any role we do not list stays greyscale
  // rather than picking up Material's default purple-tinted defaults.
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF888888),
    brightness: brightness,
    contrastLevel: highContrast ? 1.0 : 0.0,
  );
  if (brightness == Brightness.dark) {
    const white = Colors.white;
    const black = Colors.black;
    final container =
        highContrast ? const Color(0xFF262626) : const Color(0xFF1C1C1C);
    return base.copyWith(
      primary: white,
      onPrimary: black,
      primaryContainer: container,
      onPrimaryContainer: white,
      primaryFixed: container,
      primaryFixedDim: container,
      onPrimaryFixed: white,
      onPrimaryFixedVariant: white,
      secondary: white,
      onSecondary: black,
      secondaryContainer: container,
      onSecondaryContainer: white,
      secondaryFixed: container,
      secondaryFixedDim: container,
      onSecondaryFixed: white,
      onSecondaryFixedVariant: white,
      tertiary: white,
      onTertiary: black,
      tertiaryContainer: container,
      onTertiaryContainer: white,
      tertiaryFixed: container,
      tertiaryFixedDim: container,
      onTertiaryFixed: white,
      onTertiaryFixedVariant: white,
      surface: black,
      onSurface: white,
      onSurfaceVariant: highContrast ? white : const Color(0xFFAAAAAA),
      outline: highContrast ? white : const Color(0xFF333333),
      outlineVariant:
          highContrast ? const Color(0xFFBBBBBB) : const Color(0xFF222222),
      surfaceDim: black,
      surfaceBright: container,
      surfaceContainerLowest: black,
      surfaceContainerLow:
          highContrast ? const Color(0xFF101010) : const Color(0xFF0A0A0A),
      surfaceContainer:
          highContrast ? const Color(0xFF1A1A1A) : const Color(0xFF111111),
      surfaceContainerHigh:
          highContrast ? const Color(0xFF202020) : const Color(0xFF161616),
      surfaceContainerHighest: container,
      inverseSurface: white,
      onInverseSurface: black,
      inversePrimary: const Color(0xFF333333),
      surfaceTint: Colors.transparent,
      shadow: black,
      scrim: black,
      // Keep error red — functional/safety convention worth more than the
      // mono purity we'd gain by neutralizing it.
      error: const Color(0xFFFF5252),
      onError: black,
      errorContainer: const Color(0xFF3A0F0F),
      onErrorContainer: const Color(0xFFFFB4AB),
    );
  } else {
    const white = Colors.white;
    const black = Colors.black;
    final container =
        highContrast ? const Color(0xFFDDDDDD) : const Color(0xFFE8E8E8);
    return base.copyWith(
      primary: black,
      onPrimary: white,
      primaryContainer: container,
      onPrimaryContainer: black,
      primaryFixed: container,
      primaryFixedDim: container,
      onPrimaryFixed: black,
      onPrimaryFixedVariant: black,
      secondary: black,
      onSecondary: white,
      secondaryContainer: container,
      onSecondaryContainer: black,
      secondaryFixed: container,
      secondaryFixedDim: container,
      onSecondaryFixed: black,
      onSecondaryFixedVariant: black,
      tertiary: black,
      onTertiary: white,
      tertiaryContainer: container,
      onTertiaryContainer: black,
      tertiaryFixed: container,
      tertiaryFixedDim: container,
      onTertiaryFixed: black,
      onTertiaryFixedVariant: black,
      surface: white,
      onSurface: black,
      onSurfaceVariant: highContrast ? black : const Color(0xFF555555),
      outline: highContrast ? black : const Color(0xFFCCCCCC),
      outlineVariant:
          highContrast ? const Color(0xFF666666) : const Color(0xFFE5E5E5),
      surfaceDim: container,
      surfaceBright: white,
      surfaceContainerLowest: white,
      surfaceContainerLow:
          highContrast ? const Color(0xFFF4F4F4) : const Color(0xFFF8F8F8),
      surfaceContainer:
          highContrast ? const Color(0xFFEDEDED) : const Color(0xFFF3F3F3),
      surfaceContainerHigh:
          highContrast ? const Color(0xFFE4E4E4) : const Color(0xFFEEEEEE),
      surfaceContainerHighest: container,
      inverseSurface: black,
      onInverseSurface: white,
      inversePrimary: const Color(0xFFCCCCCC),
      surfaceTint: Colors.transparent,
      shadow: black,
      scrim: black,
      error: const Color(0xFFD32F2F),
      onError: white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
    );
  }
}
