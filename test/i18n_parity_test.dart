// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';

/// A key missing from a locale file renders as the raw key at runtime (see
/// `AppLocalizations.t`), so every shipped locale must carry exactly the keys
/// `en.json` has, with the same `{placeholders}`.
void main() {
  Map<String, Object?> load(String code) =>
      jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
          as Map<String, Object?>;

  final placeholder = RegExp(r'\{(\w+)\}');
  Set<String?> placeholders(Object? value) =>
      placeholder.allMatches(value as String).map((m) => m.group(1)).toSet();

  test('every supported locale has exactly the keys of en.json', () {
    final en = load('en');
    for (final locale in kSupportedAppLocales) {
      final strings = load(locale.code);
      expect(
        strings.keys.toSet(),
        en.keys.toSet(),
        reason: '${locale.code}.json key set differs from en.json',
      );
      for (final entry in strings.entries) {
        expect(
          entry.value,
          isA<String>(),
          reason: '${locale.code}.json: ${entry.key} is not a string',
        );
      }
    }
  });

  test('ios/Runner/Info.plist declares every supported locale', () {
    // iOS and the App Store take the app's languages from
    // CFBundleLocalizations, not from the Flutter assets: a language missing
    // here is missing from the App Store listing.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final array = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(array, isNotNull, reason: 'Info.plist has no CFBundleLocalizations');
    final declared = RegExp(r'<string>([^<]+)</string>')
        .allMatches(array!.group(1)!)
        .map((m) => m.group(1)!.split('-').first)
        .toSet();
    expect(declared, kSupportedAppLocales.map((l) => l.code).toSet());
  });

  test('every translation keeps the placeholders of the en string', () {
    final en = load('en');
    for (final locale in kSupportedAppLocales) {
      final strings = load(locale.code);
      for (final entry in en.entries) {
        expect(
          placeholders(strings[entry.key]),
          placeholders(entry.value),
          reason: '${locale.code}.json: ${entry.key} placeholders differ',
        );
      }
    }
  });
}
