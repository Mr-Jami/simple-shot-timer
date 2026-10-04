// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/app_localizations.dart';
import 'models/enums.dart';
import 'providers/settings_provider.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

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
    final highContrastDark = buildAppTheme(Brightness.dark, highContrast: true);
    // The in-app "High contrast" option must select the high-contrast
    // palette itself. MaterialApp only consults highContrastTheme /
    // highContrastDarkTheme when the OS accessibility flag is set, so the
    // option is wired as an explicit dark theme override; the OS-driven path
    // keeps working for every other mode.
    final forceHighContrast = themeMode == AppThemeMode.highContrast;
    return MaterialApp(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).t('app.title'),
      debugShowCheckedModeBanner: false,
      theme: forceHighContrast
          ? highContrastDark
          : buildAppTheme(Brightness.light, highContrast: false),
      darkTheme: forceHighContrast
          ? highContrastDark
          : buildAppTheme(Brightness.dark, highContrast: false),
      highContrastTheme: buildAppTheme(Brightness.light, highContrast: true),
      highContrastDarkTheme: highContrastDark,
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
      home: const MainShell(),
    );
  }
}
