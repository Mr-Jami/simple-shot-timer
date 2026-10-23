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
import 'package:simple_shot_timer/providers/clip_editor_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/screens/video_editor_screen.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/video_string_store.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/widgets/shot_badge.dart';

import 'clip_fixtures.dart';

class _MemoryStore implements VideoStringStore {
  final saved = <TimerString>[];

  @override
  Future<TimerString> insertString(TimerString s,
      {required int historyCap}) async {
    saved.add(s);
    return s.copyWith(id: saved.length);
  }

  @override
  Future<void> updateVideoString(TimerString s) async => saved.add(s);

  @override
  Future<void> deleteString(int id) async {}
}

/// No video platform in tests: the player fails to start and the editor
/// carries on over a black picture, as with a clip the phone can't play.
class _Session extends VideoSession {
  _Session() : super(Directory('session'));

  @override
  String get clipPath => 'clip.mp4';

  @override
  Future<void> dispose() async {}
}

void main() {
  // Roboto from the Flutter SDK: the test font's square glyphs overflow the
  // marker panel and the stats on a 360 dp screen.
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

  setUp(rootBundle.clear);

  final analysis = analyzePcm(
    syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
    clipSampleRate,
  );

  /// The editor over a page standing in for the Video tab.
  Future<ClipEditorState Function()> openEditor(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      videoStringStoreProvider.overrideWithValue(_MemoryStore()),
    ]);
    addTearDown(container.dispose);
    final args = ClipEditorArgs(
      clip: AnalyzedClip(
        info: const ClipInfo(
          hasAudio: true,
          durationMs: 7000,
          videoMime: 'video/avc',
        ),
        analysis: analysis,
        audioOriginMs: 0,
      ),
      session: _Session(),
      importedAt: DateTime(2026, 10, 23, 14),
    );
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
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VideoEditorScreen(args: args),
              )),
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
    return () => container.read(clipEditorProvider(args));
  }

  Future<void> selectFirstShot(WidgetTester tester) async {
    await tester.tap(find.byType(ShotBadge).first);
    await tester.pumpAndSettle();
  }

  Future<void> deleteFirstShot(WidgetTester tester) async {
    await selectFirstShot(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  final undoBar = find.text('Shot deleted');

  testWidgets('the Undo of a deleted shot goes with the editor',
      (tester) async {
    await openEditor(tester);
    await deleteFirstShot(tester);
    expect(undoBar, findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(undoBar, findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('the Undo bar times out, and goes once another edit is made',
      (tester) async {
    await openEditor(tester);
    await deleteFirstShot(tester);
    expect(undoBar, findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(undoBar, findsNothing);

    // Undo would now revert the nudge, not the delete it names.
    await deleteFirstShot(tester);
    await selectFirstShot(tester);
    expect(undoBar, findsOneWidget);
    await tester.tap(find.byTooltip('1 ms later'));
    await tester.pumpAndSettle();
    expect(undoBar, findsNothing);
  });

  testWidgets('with a screen reader the Undo bar stays, and Undo restores',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final state = await openEditor(tester);
    final shots = state().doc.activeShots.length;
    await deleteFirstShot(tester);
    expect(state().doc.activeShots, hasLength(shots - 1));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(undoBar, findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(state().doc.activeShots, hasLength(shots));
    expect(undoBar, findsNothing);
  });
}
