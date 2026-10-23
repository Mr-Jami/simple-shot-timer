// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/theme/app_theme.dart';
import 'package:simple_shot_timer/widgets/app_navigation_bar.dart';

/// Five tabs on a small phone with large text: every label in every
/// language must sit on one line inside its tab. Measured in Roboto (the
/// Android font, from the Flutter SDK) rather than the test font, whose
/// square glyphs are far wider than real text.
void main() {
  setUpAll(() async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final bytes = File('$fonts/roboto-$weight.ttf').readAsBytesSync();
      roboto.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await roboto.load();
  });

  // rootBundle caches each loaded string as a future that belongs to the
  // test that loaded it; a later test awaiting it never resumes.
  setUp(rootBundle.clear);

  /// Pumps the bar in [code] on a [width] dp screen at [textScale]; returns
  /// the five labels once that language has loaded.
  Future<List<String>> pumpBar(
    WidgetTester tester,
    String code, {
    double width = 360,
    double textScale = 1.3,
    bool showVideo = true,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    List<String>? labels;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light, highContrast: false),
      locale: Locale(code),
      supportedLocales: [for (final l in kSupportedAppLocales) Locale(l.code)],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        // Localizations keeps building with the previous language until
        // the new one has loaded.
        if (context.dateLocale == code) {
          labels = [
            for (final key in [
              'nav.timer',
              'nav.drills',
              'nav.video',
              'nav.history',
              'nav.settings',
            ])
              context.tr(key),
          ];
        }
        return Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selectedIndex: showVideo ? 4 : 3,
            onDestinationSelected: (_) {},
            showVideo: showVideo,
          ),
        );
      }),
    ));
    // AppLocalizations reads its JSON from the asset bundle, which is real
    // I/O; let it finish outside the fake clock.
    for (var i = 0; labels == null && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(labels, isNotNull, reason: 'the $code strings never loaded');
    return labels!;
  }

  RenderParagraph paragraph(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)));

  int lines(RenderParagraph p) => {
        for (final box in p.getBoxesForSelection(TextSelection(
            baseOffset: 0, extentOffset: p.text.toPlainText().length)))
          box.top.round(),
      }.length;

  testWidgets('every label fits its tab at 360 dp and 1.3x text',
      (tester) async {
    for (final locale in kSupportedAppLocales) {
      final labels = await pumpBar(tester, locale.code);
      expect(tester.takeException(), isNull, reason: locale.code);
      final tab = 360 / labels.length;
      for (final label in labels) {
        final p = paragraph(tester, label);
        expect(lines(p), 1, reason: '${locale.code}: "$label" wraps');
        expect(p.size.width, lessThanOrEqualTo(tab),
            reason: '${locale.code}: "$label" is wider than its tab');
      }
    }
  });

  testWidgets('no Video tab where clips cannot be read yet', (tester) async {
    expect(clipAudioAvailableOn(TargetPlatform.android), isTrue);
    await pumpBar(tester, 'en',
        showVideo: clipAudioAvailableOn(TargetPlatform.iOS));
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Video'), findsNothing);
  });

  testWidgets('labels keep the theme size when they fit', (tester) async {
    final labels = await pumpBar(tester, 'en', width: 412, textScale: 1);
    for (final label in labels) {
      expect(paragraph(tester, label).text.style?.fontSize, 12);
    }
  });

  testWidgets('shrinks only as far as the longest label needs', (tester) async {
    final labels = await pumpBar(tester, 'de');
    final size = paragraph(tester, labels.first).text.style!.fontSize!;
    expect(size, lessThan(12));
    // Half a point larger and "Einstellungen" would not fit.
    final style = paragraph(tester, 'Einstellungen').text.style!;
    final wider = TextPainter(
      text: TextSpan(
          text: 'Einstellungen',
          style: style.copyWith(
              fontSize: size + 0.5, fontWeight: FontWeight.w600)),
      textScaler: const TextScaler.linear(1.3),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(wider.width, greaterThan(360 / 5 - 8));
    wider.dispose();
  });
}
