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
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/settings_provider.dart';
import 'package:simple_shot_timer/providers/video_export_provider.dart';
import 'package:simple_shot_timer/screens/video_export_sheet.dart';

void main() {
  setUp(rootBundle.clear);

  testWidgets('fits a small phone; its choices are kept; Share returns',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
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
              onPressed: () async => chosen = await showExportSheet(context),
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

    final share = find.widgetWithText(OutlinedButton, 'Share');
    expect(tester.getRect(share).bottom, lessThanOrEqualTo(780));
    await tester.tap(find.byTooltip('Bottom right'));
    await tester.tap(find.text('Full'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final settings = container.read(settingsProvider);
    expect(settings.hudCorner, HudCorner.bottomRight);
    expect(settings.hudStyle, HudStyle.full);
    expect(settings.hudEndCard, isFalse);

    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(chosen, ExportTarget.share);
  });
}
