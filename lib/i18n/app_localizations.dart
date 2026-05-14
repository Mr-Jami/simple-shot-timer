import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One entry per language we ship.
///
/// To add a new language:
///   1. Drop a JSON file at `assets/i18n/{code}.json` mirroring `en.json`.
///   2. Add one `AppLocale(...)` line below.
/// That's it — pubspec already globs the whole `assets/i18n/` directory.
class AppLocale {
  const AppLocale({
    required this.code,
    required this.displayName,
  });

  /// IETF code, e.g. `en`, `de`. Also the JSON file's basename.
  final String code;

  /// Shown in the language picker (kept in the language's own script so users
  /// can recognize their own language even when the current UI is foreign).
  final String displayName;

  Locale get locale => Locale(code);
}

const List<AppLocale> kSupportedAppLocales = <AppLocale>[
  AppLocale(code: 'en', displayName: 'English'),
  AppLocale(code: 'de', displayName: 'Deutsch'),
  AppLocale(code: 'es', displayName: 'Español'),
  AppLocale(code: 'fr', displayName: 'Français'),
  AppLocale(code: 'ru', displayName: 'Русский'),
];

class AppLocalizations {
  AppLocalizations(this.locale, this._strings);

  final Locale locale;
  final Map<String, String> _strings;

  static AppLocalizations of(BuildContext context) {
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(l != null, 'AppLocalizations not found in widget tree');
    return l!;
  }

  /// Look up a string by key. Unknown keys fall back to the key itself so
  /// missing translations are visible during development without crashing.
  String t(String key, {Map<String, Object?>? args}) {
    final raw = _strings[key] ?? key;
    if (args == null || args.isEmpty) return raw;
    var out = raw;
    args.forEach((name, value) {
      out = out.replaceAll('{$name}', '${value ?? ''}');
    });
    return out;
  }

  static Future<AppLocalizations> _load(Locale locale) async {
    final code = locale.languageCode;
    final path = 'assets/i18n/$code.json';
    final jsonStr = await rootBundle.loadString(path);
    final decoded = json.decode(jsonStr) as Map<String, dynamic>;
    final flat = <String, String>{};
    for (final entry in decoded.entries) {
      final v = entry.value;
      if (v is String) flat[entry.key] = v;
    }
    return AppLocalizations(locale, flat);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      kSupportedAppLocales.any((l) => l.code == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations._load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Sugar so call sites can write `context.tr('home.ready')`.
extension AppLocalizationsX on BuildContext {
  String tr(String key, {Map<String, Object?>? args}) =>
      AppLocalizations.of(this).t(key, args: args);
}
