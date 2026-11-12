// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/settings_provider.dart';
import 'package:simple_shot_timer/providers/video_export_provider.dart';
import 'package:simple_shot_timer/screens/video_export_sheet.dart';
import 'package:simple_shot_timer/services/settings_service.dart';

void main() {
  setUp(rootBundle.clear);

  /// The sheet open on a 360 x 780 phone, over a clip that is [tallFrame]
  /// or not. Gives the settings as they are now, what was stored, and what
  /// the sheet returned.
  Future<
      ({
        AppSettings Function() settings,
        AppSettings Function() stored,
        ExportTarget? Function() chosen,
      })> openSheet(
    WidgetTester tester, {
    required bool tallFrame,
    Map<String, Object> saved = const {},
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    ExportTarget? chosen;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => chosen = await showExportSheet(context,
                  stringMs: 12400, wholeMs: 161000, tallFrame: tallFrame),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    // AppLocalizations reads its JSON from the asset bundle: real I/O.
    for (var i = 0; find.text('open').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (
      settings: () => container.read(settingsProvider),
      stored: () => SettingsService(prefs).load(),
      chosen: () => chosen,
    );
  }

  final share = find.widgetWithText(OutlinedButton, 'Share');
  final clear = find.widgetWithText(
      SwitchListTile, 'Keep clear of Reels and TikTok buttons');

  testWidgets('fits a small phone; its choices are kept; Share returns',
      (tester) async {
    final sheet = await openSheet(tester, tallFrame: false);

    expect(tester.getRect(share).bottom, lessThanOrEqualTo(780));
    expect(find.text('String · 0:12'), findsOneWidget);
    await tester.tap(find.text('Whole video · 2:41'));
    await tester.tap(find.byTooltip('Bottom right'));
    await tester.tap(find.text('Full'));
    // The end card's, the only switch for a clip that isn't tall.
    expect(clear, findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final settings = sheet.settings();
    expect(settings.hudCorner, HudCorner.bottomRight);
    expect(settings.hudStyle, HudStyle.full);
    expect(settings.hudEndCard, isFalse);
    expect(settings.hudClearOfButtons, isFalse);
    expect(settings.exportWholeVideo, isTrue);

    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(sheet.chosen(), ExportTarget.share);
  });

  testWidgets(
      'a tall clip can keep clear of the apps\' buttons: off at first, and '
      'the choice is kept', (tester) async {
    final sheet = await openSheet(tester, tallFrame: true);

    expect(tester.getRect(share).bottom, lessThanOrEqualTo(780));
    expect(tester.widget<SwitchListTile>(clear).value, isFalse);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(clear).value, isTrue);
    expect(sheet.settings().hudClearOfButtons, isTrue);
    // The end card's switch is another one.
    expect(sheet.settings().hudEndCard, isTrue);
    expect(sheet.stored().hudClearOfButtons, isTrue);
  });

  testWidgets('the choice stays on, unseen, for a clip that isn\'t tall',
      (tester) async {
    final sheet = await openSheet(tester,
        tallFrame: false, saved: {'flutter.video_hud_clear_of_buttons': true});

    expect(clear, findsNothing);
    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    expect(sheet.stored().hudClearOfButtons, isTrue);
  });
}
