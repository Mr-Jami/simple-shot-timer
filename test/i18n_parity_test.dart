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

  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final iosLocalizations = RegExp(r'<string>([^<]+)</string>')
      .allMatches(
        RegExp(
              r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
              dotAll: true,
            ).firstMatch(plist)?.group(1) ??
            '',
      )
      .map((m) => m.group(1)!)
      .toList();

  test('ios/Runner/Info.plist declares every supported locale', () {
    // iOS only runs the app in the languages of CFBundleLocalizations, so a
    // language missing here leaves system UI such as the microphone prompt in
    // English.
    expect(iosLocalizations.map((l) => l.split('-').first).toSet(),
        kSupportedAppLocales.map((l) => l.code).toSet());
  });

  test('every iOS localization ships an InfoPlist.strings', () {
    // The App Store lists the languages of the <lang>.lproj folders in the
    // bundle, not CFBundleLocalizations or the Flutter assets: a language
    // without its folder is missing from the App Store page.
    const micKey = 'NSMicrophoneUsageDescription';
    String? micText(String source, RegExp pattern) =>
        pattern.firstMatch(source)?.group(1);
    final stringsEntry = RegExp('"$micKey"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)";');
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    for (final lang in iosLocalizations) {
      final path = '$lang.lproj/InfoPlist.strings';
      final file = File('ios/Runner/$path');
      expect(file.existsSync(), isTrue, reason: 'missing ios/Runner/$path');
      expect(micText(file.readAsStringSync(), stringsEntry), isNotEmpty,
          reason: '$path has no $micKey');
      expect(project, contains(path),
          reason: '$path is not in the Xcode project, so it is not bundled');
    }
    expect(
      micText(File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync(),
          stringsEntry),
      micText(plist, RegExp('<key>$micKey</key>\\s*<string>([^<]*)</string>')),
      reason: 'en.lproj overrides Info.plist and must say the same',
    );
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
