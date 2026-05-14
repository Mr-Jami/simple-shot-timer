import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/app_localizations.dart';
import 'models/enums.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';

class SimpleShotTimerApp extends ConsumerWidget {
  const SimpleShotTimerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsProvider.select((s) => s.themeMode),
    );
    final localeCode = ref.watch(
      settingsProvider.select((s) => s.localeCode),
    );
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light, highContrast: false),
      darkTheme: _buildTheme(Brightness.dark, highContrast: false),
      highContrastTheme: _buildTheme(Brightness.light, highContrast: true),
      highContrastDarkTheme: _buildTheme(Brightness.dark, highContrast: true),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.highContrast => ThemeMode.dark,
      },
      locale: localeCode == null ? null : Locale(localeCode),
      supportedLocales: [
        for (final l in kSupportedAppLocales) l.locale,
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness, {required bool highContrast}) {
    final scheme = _monochromeScheme(brightness, highContrast: highContrast);
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
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      textTheme: const TextTheme().apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }

  /// True-monochrome ColorScheme — pure black/white headline pair, neutral grey
  /// container variants, no hue tinting. Matches the two-tone app icon.
  ColorScheme _monochromeScheme(
    Brightness brightness, {
    required bool highContrast,
  }) {
    // Use a neutral grey seed so any unspecified roles stay greyscale rather
    // than picking up Material's default purple-tinted defaults.
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF888888),
      brightness: brightness,
      contrastLevel: highContrast ? 1.0 : 0.0,
    );
    if (brightness == Brightness.dark) {
      return base.copyWith(
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.white,
        onSecondary: Colors.black,
        tertiary: Colors.white,
        onTertiary: Colors.black,
        surface: const Color(0xFF000000),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFAAAAAA),
        outline: const Color(0xFF333333),
        outlineVariant: const Color(0xFF222222),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
        inverseSurface: Colors.white,
        onInverseSurface: Colors.black,
        surfaceTint: Colors.transparent,
        // Keep error red — functional/safety convention worth more than the
        // mono purity we'd gain by neutralizing it.
        error: const Color(0xFFFF5252),
        onError: Colors.black,
        errorContainer: const Color(0xFF3A0F0F),
        onErrorContainer: const Color(0xFFFFB4AB),
      );
    } else {
      return base.copyWith(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        tertiary: Colors.black,
        onTertiary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        onSurfaceVariant: const Color(0xFF555555),
        outline: const Color(0xFFCCCCCC),
        outlineVariant: const Color(0xFFE5E5E5),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF8F8F8),
        surfaceContainer: const Color(0xFFF3F3F3),
        surfaceContainerHigh: const Color(0xFFEEEEEE),
        surfaceContainerHighest: const Color(0xFFE8E8E8),
        inverseSurface: Colors.black,
        onInverseSurface: Colors.white,
        surfaceTint: Colors.transparent,
        error: const Color(0xFFD32F2F),
        onError: Colors.white,
        errorContainer: const Color(0xFFFFDAD6),
        onErrorContainer: const Color(0xFF410002),
      );
    }
  }
}
