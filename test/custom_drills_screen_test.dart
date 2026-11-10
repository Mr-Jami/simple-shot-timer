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
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/settings_provider.dart';
import 'package:simple_shot_timer/screens/custom_drills_screen.dart';
import 'package:simple_shot_timer/services/settings_service.dart';

void main() {
  setUp(rootBundle.clear);

  testWidgets('a drill shows its sensitivity and sets it when tapped (#68)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = SettingsService(prefs);
    await service.save(const AppSettings(sensitivityPercent: 15));
    await service.saveDrills([
      CustomDrill(
        id: 1,
        name: 'Dry fire',
        config:
            DrillConfig.fromSettings(const AppSettings(sensitivityPercent: 40)),
      ),
      CustomDrill(
        id: 2,
        name: 'Range',
        config:
            DrillConfig.fromSettings(const AppSettings(sensitivityPercent: 15)),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: CustomDrillsScreen()),
      ),
    ));
    // AppLocalizations reads its JSON from the asset bundle: real I/O.
    for (var i = 0; find.text('Dry fire').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    Finder tile(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ListTile));
    Finder inTile(String name, Finder what) =>
        find.descendant(of: tile(name), matching: what);

    // Each line ends with the drill's own sensitivity.
    expect(inTile('Dry fire', find.textContaining('· 40% sensitivity')),
        findsOneWidget);
    expect(inTile('Range', find.textContaining('· 15% sensitivity')),
        findsOneWidget);
    // The two drills differ in nothing else, and the settings match "Range".
    expect(inTile('Range', find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(inTile('Dry fire', find.byIcon(Icons.check_circle)), findsNothing);

    await tester.tap(find.text('Dry fire'));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).sensitivityPercent, 40);
    expect(inTile('Dry fire', find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(inTile('Range', find.byIcon(Icons.check_circle)), findsNothing);
    expect(find.text('Applied “Dry fire”'), findsOneWidget);
  });
}
