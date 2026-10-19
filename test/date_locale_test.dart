// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';

/// History, Review and the home screen's "Saved" line format dates with
/// `context.dateLocale`. Without a locale, DateFormat uses intl's default
/// (en_US), so month names and the clock stayed English in every language.
void main() {
  final when = DateTime(2026, 10, 19, 20, 15);

  // rootBundle caches each loaded string as a future that belongs to the
  // test that loaded it; a later test awaiting it never resumes.
  setUp(rootBundle.clear);

  Future<String> formatIn(WidgetTester tester, String code) async {
    String? out;
    await tester.pumpWidget(MaterialApp(
      locale: Locale(code),
      supportedLocales: [for (final l in kSupportedAppLocales) Locale(l.code)],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        // Until the new language has loaded, Localizations keeps building
        // with the previous one; only take the result in the right language.
        if (context.dateLocale == code) {
          out = DateFormat.yMMMd(context.dateLocale).add_jm().format(when);
        }
        return const SizedBox();
      }),
    ));
    // AppLocalizations reads its JSON from the asset bundle, which is real
    // I/O; let it finish outside the fake clock.
    for (var i = 0; out == null && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(out, isNotNull, reason: 'the $code strings never loaded');
    return out!;
  }

  testWidgets('dates follow the app language', (tester) async {
    final en = await formatIn(tester, 'en');
    expect(en, contains('Oct 19, 2026'));
    expect(await formatIn(tester, 'de'),
        allOf(contains('Okt.'), contains('20:15')));
    expect(await formatIn(tester, 'fr'), contains('oct.'));
    expect(await formatIn(tester, 'ru'), contains('окт.'));
  });

  test('no DateFormat in lib/ is created without a locale', () {
    final bare = RegExp(r'DateFormat(\.\w+)?\(\s*\)');
    final offenders = [
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          for (final line in f.readAsLinesSync())
            if (bare.hasMatch(line)) '${f.path}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: 'pass context.dateLocale');
  });

  testWidgets('every app language has its own date format', (tester) async {
    final en = await formatIn(tester, 'en');
    for (final locale in kSupportedAppLocales.where((l) => l.code != 'en')) {
      expect(await formatIn(tester, locale.code), isNot(en),
          reason: '${locale.code} dates fall back to English');
    }
  });
}
