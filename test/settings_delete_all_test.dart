// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/history_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/screens/settings_screen.dart';
import 'package:simple_shot_timer/services/video/export_plan.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';

class _History extends HistoryNotifier {
  var deleted = false;

  @override
  Future<List<TimerString>> build() async => const [];

  @override
  Future<void> deleteAll() async => deleted = true;
}

void main() {
  setUp(rootBundle.clear);

  testWidgets(
      'Delete all data and settings also removes video files and exports',
      (tester) async {
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('wipe_test')))!;
    final temp = Directory('${root.path}/tmp');
    final gone = [
      File('${root.path}/video_work/1792744218314177/1000055566.mp4'),
      File('${temp.path}/${ExportPlan.fileName(DateTime(2026), 21460)}'),
      File(
          '${temp.path}/share_plus/${ExportPlan.fileName(DateTime(2026), 9310)}'),
      // A copy the photo picker left behind.
      File('${temp.path}/506b8b0f-c91a-4a9b-838c-1194a79dbd78/1000055609.mp4'),
      File('${temp.path}/string_42_1761220000000.csv'),
    ];
    final kept = File('${temp.path}/someone_else.txt');
    await tester.runAsync(() async {
      for (final f in [...gone, kept]) {
        await f.create(recursive: true);
      }
    });
    // ExportService finds the temporary folder through path_provider.
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        paths,
        (call) async =>
            call.method == 'getTemporaryDirectory' ? temp.path : null);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));

    SharedPreferences.setMockInitialValues({'flutter.video_hud_style': 'full'});
    final prefs = await SharedPreferences.getInstance();
    final history = _History();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      historyProvider.overrideWith(() => history),
      videoWorkDirProvider.overrideWithValue(
          VideoWorkDir(root: () async => Directory('${root.path}/video_work'))),
    ]);
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
        home: Scaffold(body: SettingsScreen()),
      ),
    ));
    // AppLocalizations reads its JSON from the asset bundle: real I/O.
    for (var i = 0; find.text('Settings').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    final deleteAll = find.text('Delete all data and settings');
    await tester.scrollUntilVisible(deleteAll, 300);
    await tester.tap(deleteAll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    // The wipe deletes real files.
    final done = find.text('All data and settings deleted');
    for (var i = 0; done.evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    expect(done, findsOneWidget);
    expect(history.deleted, isTrue);
    expect(prefs.getKeys(), isEmpty);
    final exists = await tester.runAsync(() async => [
          for (final f in [...gone, kept]) await f.exists()
        ]);
    expect(exists, [false, false, false, false, false, true]);
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
