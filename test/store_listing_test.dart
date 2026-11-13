// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';

/// The store listings in fastlane/metadata are uploaded as they are by
/// update-store-listings.yml, and the stores reject a field over its limit,
/// so these tests check the limits and that every app language has a
/// listing in both stores.
void main() {
  const root = 'fastlane/metadata';

  // App language -> (Google Play locale, App Store Connect locale).
  const storeLocales = {
    'en': ('en-US', 'en-US'),
    'de': ('de-DE', 'de-DE'),
    'es': ('es-ES', 'es-ES'),
    'fi': ('fi-FI', 'fi'),
    'fr': ('fr-FR', 'fr-FR'),
    'pl': ('pl-PL', 'pl'),
    'pt': ('pt-BR', 'pt-BR'),
    'ru': ('ru-RU', 'ru'),
  };

  // File name -> character limit. Files listed in `required` must exist in
  // every locale folder of that store. release_notes (What's New) is not
  // here on purpose: update-store-listings.yml writes it from the GitHub
  // Releases, so a hand-written one would be overwritten.
  const playLimits = {
    'title': 30,
    'short_description': 80,
    'full_description': 4000,
  };
  const playRequired = {'title', 'short_description', 'full_description'};
  const appStoreLimits = {
    'name': 30,
    'subtitle': 30,
    'description': 4000,
    'keywords': 100,
    'promotional_text': 170,
    'support_url': 255,
    'marketing_url': 255,
    'privacy_url': 255,
  };
  const appStoreRequired = {
    'name',
    'description',
    'support_url',
    'privacy_url',
  };

  List<Directory> locales(String store) =>
      Directory('$root/$store').listSync().whereType<Directory>().toList();

  String name(FileSystemEntity e) =>
      e.uri.pathSegments.where((s) => s.isNotEmpty).last;

  test('every app language has a Google Play and an App Store listing', () {
    for (final locale in kSupportedAppLocales) {
      final codes = storeLocales[locale.code];
      expect(codes, isNotNull,
          reason: 'add ${locale.code} to storeLocales and write its listing');
      expect(Directory('$root/android/${codes!.$1}').existsSync(), isTrue,
          reason: 'no Google Play listing for ${locale.code}');
      expect(Directory('$root/ios/${codes.$2}').existsSync(), isTrue,
          reason: 'no App Store listing for ${locale.code}');
    }
  });

  void checkStore(
    String store,
    Map<String, int> limits,
    Set<String> required,
  ) {
    final dirs = locales(store);
    expect(dirs, isNotEmpty);
    for (final dir in dirs) {
      final files = {
        for (final f in dir.listSync().whereType<File>())
          name(f).replaceFirst(RegExp(r'\.txt$'), ''): f,
      };
      expect(files.keys.toSet().containsAll(required), isTrue,
          reason: '$store/${name(dir)} is missing one of $required');
      for (final MapEntry(key: field, value: file) in files.entries) {
        final limit = limits[field];
        expect(limit, isNotNull,
            reason: '$store/${name(dir)}/${name(file)} is not a known field');
        // Line breaks count once: a Windows checkout has CRLF, the upload
        // job (Linux) sends LF.
        final text = file.readAsStringSync().replaceAll('\r\n', '\n').trim();
        expect(text, isNotEmpty, reason: '$store/${name(dir)}/$field is empty');
        expect(text.runes.length, lessThanOrEqualTo(limit!),
            reason: '$store/${name(dir)}/$field is over $limit characters');
      }
    }
  }

  test('Google Play listings fit the store limits', () {
    checkStore('android', playLimits, playRequired);
  });

  test('App Store listings fit the store limits', () {
    checkStore('ios', appStoreLimits, appStoreRequired);
  });

  // The workflow uploads these as they are. Play takes two to eight phone
  // screenshots per language, without transparency and no side more than
  // twice the other; the set is 1080x1920.
  test('every Google Play listing has its phone screenshots', () {
    for (final dir in locales('android')) {
      final shots = Directory('${dir.path}/images/phoneScreenshots');
      expect(shots.existsSync(), isTrue,
          reason: 'android/${name(dir)} has no phone screenshots');
      final files = shots.listSync().whereType<File>().toList();
      expect(files.length, inInclusiveRange(2, 8),
          reason: 'android/${name(dir)}: Play takes 2 to 8 screenshots');
      for (final file in files) {
        final where = 'android/${name(dir)}/${name(file)}';
        final bytes = file.readAsBytesSync();
        expect(bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10],
            reason: '$where is not a PNG');
        int be(int at) => bytes.buffer.asByteData().getUint32(at); // big-endian
        expect((be(16), be(20)), (1080, 1920), reason: '$where: wrong size');
        // IHDR colour type 2 is RGB; 4 and 6 carry alpha.
        expect(bytes[25], 2, reason: '$where has an alpha channel');
      }
    }
  });
}
