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
    // iOS takes the app's languages from this list and from the <lang>.lproj
    // folders. The next tests check that every language here has its folder.
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
    for (final lang in iosLocalizations) {
      final path = '$lang.lproj/InfoPlist.strings';
      final file = File('ios/Runner/$path');
      expect(file.existsSync(), isTrue, reason: 'missing ios/Runner/$path');
      expect(micText(file.readAsStringSync(), stringsEntry), isNotEmpty,
          reason: '$path has no $micKey');
    }
    expect(
      micText(File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync(),
          stringsEntry),
      micText(plist, RegExp('<key>$micKey</key>\\s*<string>([^<]*)</string>')),
      reason: 'en.lproj overrides Info.plist and must say the same',
    );
  });

  test('the Runner target bundles the InfoPlist.strings of every language', () {
    // Only an Xcode build would notice a file missing from the build, and CI
    // builds iOS only on release. The app would then ship without that
    // .lproj folder and the App Store page would lose the language.
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final group = RegExp(
      r'(\w{24}) /\* InfoPlist\.strings \*/ = \{\s*isa = PBXVariantGroup;'
      r'\s*children = \(([^)]*)\)',
    ).firstMatch(project);
    expect(group, isNotNull,
        reason: 'project.pbxproj has no InfoPlist.strings variant group');
    String? langOf(String fileRef) => RegExp(
          '$fileRef /\\*[^*]*\\*/ = \\{isa = PBXFileReference;'
          '[^}]*path = "?([^";]+)\\.lproj/InfoPlist\\.strings"?;',
        ).firstMatch(project)?.group(1);
    expect(
      [
        for (final m in RegExp(r'\w{24}').allMatches(group!.group(2)!))
          langOf(m[0]!),
      ],
      unorderedEquals(iosLocalizations),
      reason: 'the InfoPlist.strings variant group must have one '
          '<lang>.lproj/InfoPlist.strings per CFBundleLocalizations entry',
    );

    final runnerPhases = RegExp(
          r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?'
          r'buildPhases = \(([^)]*)\)',
          dotAll: true,
        ).firstMatch(project)?.group(1) ??
        '';
    final resourcesPhase =
        RegExp(r'(\w{24}) /\* Resources \*/').firstMatch(runnerPhases)?[1];
    final resources = RegExp(
          '$resourcesPhase /\\* Resources \\*/ = \\{[^}]*?files = \\(([^)]*)\\)',
        ).firstMatch(project)?.group(1) ??
        '';
    final buildFiles = RegExp(
      '(\\w{24}) /\\*[^*]*\\*/ = \\{isa = PBXBuildFile; fileRef = ${group[1]} ',
    ).allMatches(project).map((m) => m[1]!);
    expect(buildFiles.any(resources.contains), isTrue,
        reason: 'InfoPlist.strings is not in Copy Bundle Resources of the '
            'Runner target');
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
