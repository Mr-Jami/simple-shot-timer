// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/services/video/marker_doc.dart';
import 'package:simple_shot_timer/theme/app_theme.dart';
import 'package:simple_shot_timer/widgets/editor/marker_panel.dart';

import 'roboto.dart';

/// The video editor's marker panel on a small phone with large text, in
/// every language: with a shot selected (nudges, Delete, Last shot) and
/// without (Set START, + Shot). Measured in Roboto, as the tab labels are.
void main() {
  setUpAll(loadRoboto);
  setUp(rootBundle.clear);

  const shot = EditShot(id: 1, ms: 2620, detectedMs: 2620);
  const shots = [EditShot(id: 0, ms: 2200, detectedMs: 2200), shot];

  for (final language in kSupportedAppLocales) {
    for (final selected in [shot, null]) {
      final what = selected == null ? 'Set START and + Shot' : 'a shot';
      testWidgets('$what fit at 360 dp and 1.3x text in ${language.code}',
          (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(360 * 3, 800 * 3);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var loaded = false;
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(Brightness.dark, highContrast: false),
          locale: Locale(language.code),
          supportedLocales: [
            for (final l in kSupportedAppLocales) Locale(l.code)
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(builder: (context) {
            // The previous language shows until the new one has loaded.
            loaded = context.dateLocale == language.code;
            return Scaffold(
              body: MarkerPanel(
                selected: selected,
                shots: shots,
                startMs: selected == null ? null : 1000,
                onSetStart: () {},
                onAddShot: () {},
                onNudgeStart: () {},
                onNudge: (_, __) {},
                onNudgeEnd: () {},
                onDelete: (_) {},
                onLastShot: (_) {},
                onDeselect: () {},
              ),
            );
          }),
        ));
        // AppLocalizations reads its JSON from the asset bundle: real I/O.
        for (var i = 0; !loaded && i < 200; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        expect(loaded, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
