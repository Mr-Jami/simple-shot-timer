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
