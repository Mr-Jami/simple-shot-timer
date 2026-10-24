// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:simple_shot_timer/services/timer_ports.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_exporter.dart';
import 'package:simple_shot_timer/services/video/export_plan.dart';
import 'package:simple_shot_timer/services/video/hud.dart';
import 'package:simple_shot_timer/services/video/hud_painter.dart';
import 'package:simple_shot_timer/services/video/video_string_store.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';
import 'package:simple_shot_timer/widgets/shot_badge.dart';
import 'package:simple_shot_timer/widgets/timeline/shot_timeline.dart';

import 'clip_fixtures.dart';
import 'roboto.dart';

class _MemoryStore implements VideoStringStore {
  final saved = <TimerString>[];

  /// Fails the next write, as a full disk would.
  var failNext = false;

  @override
  Future<TimerString> insertString(TimerString s,
      {required int historyCap}) async {
    if (failNext) {
      failNext = false;
      throw Exception('disk full');
    }
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

/// Export just far enough to reach the overlay images.
class _Awake implements RunEnvironment {
  @override
  Future<void> setKeepAwake(bool on) async {}
  @override
  Future<void> setForeground(bool on) async {}
  @override
  Future<void> vibrate() async {}
}

class _NoExporter implements ClipExporter {
  @override
  Future<void> export(
    ExportRequest request, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> encoderNeedsColorFix() async => false;
}

void main() {
  // Roboto from the Flutter SDK: the test font's square glyphs overflow the
  // marker panel and the stats on a 360 dp screen.
  setUpAll(loadRoboto);

  setUp(rootBundle.clear);

  late _MemoryStore store;

  final analysis = analyzePcm(
    syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
    clipSampleRate,
  );

  /// The editor over a page standing in for the Video tab, on the 7 s clip
  /// unless [seconds] asks for a longer one.
  Future<ClipEditorState Function()> openEditor(
    WidgetTester tester, {
    int seconds = 7,
    List<Override> overrides = const [],
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = _MemoryStore();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      videoStringStoreProvider.overrideWithValue(store),
      ...overrides,
    ]);
    addTearDown(container.dispose);
    final args = ClipEditorArgs(
      clip: AnalyzedClip(
        info: ClipInfo(
          hasAudio: true,
          durationMs: seconds * 1000,
          videoMime: 'video/avc',
        ),
        analysis: seconds == 7
            ? analysis
            : analyzePcm(
                syntheticClip(
                  seconds: seconds.toDouble(),
                  extra: (x) => addBeep(x, 1.0, 300),
                ),
                clipSampleRate,
              ),
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

  testWidgets('Whole video exports the clip from its first frame to its last',
      (tester) async {
    ExportPlan? exported;
    // Long enough that the string (to 4 s after the last shot, 8.1 s) isn't
    // the whole clip.
    await openEditor(tester, seconds: 12, overrides: [
      runEnvironmentProvider.overrideWithValue(_Awake()),
      clipExporterProvider.overrideWithValue(_NoExporter()),
      hudFrameRendererProvider.overrideWithValue((
          {required Directory dir,
          required ExportPlan plan,
          required HudString string,
          required HudOptions options,
          required HudLabels labels,
          ui.Image? logo,
          void Function(double fraction)? onProgress,
          CancelToken? cancel}) async {
        exported = plan;
        throw const ExportException(ExportError.cancelled);
      }),
    ]);
    await tester.tap(find.text('Export video'));
    await tester.pumpAndSettle();
    expect(find.text('String · 0:08'), findsOneWidget);
    await tester.tap(find.text('Whole video · 0:12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect((exported!.startMs, exported!.endMs), (0, 12000));
  });

  testWidgets('Back saves the string once', (tester) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(store.saved, hasLength(1));
  });

  testWidgets('a failed save asks until a button is picked', (tester) async {
    await openEditor(tester);
    store.failNext = true;
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    final asking = find.text('Couldn’t save');
    expect(asking, findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(asking, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(asking, findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(store.saved, hasLength(1));
  });

  testWidgets('going to the background saves the string', (tester) async {
    await openEditor(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(store.saved, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('Next takes the selection along; a drag moves that shot',
      (tester) async {
    final state = await openEditor(tester);
    final before = state().doc.activeShots;
    await selectFirstShot(tester);
    expect(state().selectedId, before[0].id);
    await tester.tap(find.byTooltip('Next marker'));
    await tester.pumpAndSettle();
    expect(state().selectedId, before[1].id);
    await tester.drag(find.byType(ShotTimeline), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(state().doc.shotById(before[0].id)!.ms, before[0].ms);
    expect(state().doc.shotById(before[1].id)!.ms, isNot(before[1].ms));
  });
}
