// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
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
import 'package:simple_shot_timer/widgets/clip_video.dart';
import 'package:simple_shot_timer/widgets/editor/editor_transport.dart';
import 'package:simple_shot_timer/widgets/editor/marker_panel.dart';
import 'package:simple_shot_timer/widgets/shot_badge.dart';
import 'package:simple_shot_timer/widgets/timeline/shot_timeline.dart';
import 'package:simple_shot_timer/widgets/timeline/timeline_controller.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

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

  /// Fails every delete while set.
  var failDelete = false;

  @override
  Future<void> deleteString(int id) async {
    if (failDelete) throw Exception('database locked');
  }
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

/// A video platform whose clips start and play: each position report (every
/// 100 ms while playing) is 100 ms on from the last.
class _PlayingVideo extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  var _position = Duration.zero;

  /// What the player was asked for, in order: a seek's ms, or 'play'.
  final asked = <Object>[];

  /// While set, seeks land only once it completes, as on a slow decoder.
  Completer<void>? slowSeek;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _events.length;
    _events[id] = StreamController<VideoEvent>()
      ..add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 7),
        size: const Size(1920, 1080),
      ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events[playerId]!.close();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async => asked.add('play');

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    asked.add(position.inMilliseconds);
    await slowSeek?.future;
    _position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      _position += const Duration(milliseconds: 100);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand();
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

  @override
  bool get straightAlpha => false;
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
  /// unless [seconds] asks for a longer one, or one without a [beep].
  Future<ClipEditorState Function()> openEditor(
    WidgetTester tester, {
    int seconds = 7,
    bool beep = true,
    String language = 'en',
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
        analysis: seconds == 7 && beep
            ? analysis
            : analyzePcm(
                syntheticClip(
                  seconds: seconds.toDouble(),
                  extra: beep ? (x) => addBeep(x, 1.0, 300) : null,
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
        locale: Locale(language),
        supportedLocales: [
          for (final l in kSupportedAppLocales) Locale(l.code)
        ],
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

  /// Exports up to the overlay images, handing their plan to [onPlan].
  List<Override> exportToOverlay(void Function(ExportPlan plan) onPlan) => [
        runEnvironmentProvider.overrideWithValue(_Awake()),
        clipExporterProvider.overrideWithValue(_NoExporter()),
        hudFrameRendererProvider.overrideWithValue((
            {required Directory dir,
            required ExportPlan plan,
            required HudString string,
            required HudOptions options,
            required HudLabels labels,
            ui.Image? logo,
            bool straightAlpha = false,
            void Function(double fraction)? onProgress,
            CancelToken? cancel}) async {
          onPlan(plan);
          throw const ExportException(ExportError.cancelled);
        }),
      ];

  testWidgets('Whole video exports the clip from its first frame to its last',
      (tester) async {
    ExportPlan? exported;
    // Long enough that the string (to 4 s after the last shot, 8.1 s) isn't
    // the whole clip.
    await openEditor(tester,
        seconds: 12, overrides: exportToOverlay((plan) => exported = plan));
    await tester.tap(find.text('Export video'));
    await tester.pumpAndSettle();
    expect(find.text('String · 0:08'), findsOneWidget);
    await tester.tap(find.text('Whole video · 0:12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect((exported!.startMs, exported!.endMs), (0, 12000));
  });

  testWidgets('a paused editor draws nothing; playing, the timeline follows',
      (tester) async {
    final platform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _PlayingVideo();
    addTearDown(() => VideoPlayerPlatform.instance = platform);
    // Opening settles: no frame after frame while the video stands still.
    await openEditor(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    final from = timeline.playheadMs;

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(timeline.playheadMs, greaterThanOrEqualTo(from + 400));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Closed while the fake platform is still in place.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  /// The editor on a playing video, its timeline flicked and still gliding,
  /// and every seek from here on slow to land.
  Future<(_PlayingVideo, TimelineController)> openGliding(
    WidgetTester tester, {
    bool beep = true,
  }) async {
    final platform = VideoPlayerPlatform.instance;
    final video = _PlayingVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = platform);
    await openEditor(tester, beep: beep);
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    await tester.flingFrom(tester.getCenter(find.byType(ShotTimeline)),
        const Offset(-100, 0), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(timeline.motion, TimelineMotion.fling, reason: 'still gliding');
    video.slowSeek = Completer<void>();
    video.asked.clear();
    return (video, timeline);
  }

  /// Lets the slow seeks land, then closes the editor while the fake
  /// platform is still in place.
  Future<void> landAndClose(WidgetTester tester, _PlayingVideo video) async {
    video.slowSeek?.complete();
    video.slowSeek = null;
    await tester.pump();
    if (find.byTooltip('Pause').evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Pause'));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  }

  testWidgets(
      'Play while the timeline glides stops it and plays from there, once '
      'the seek has landed', (tester) async {
    final (video, timeline) = await openGliding(tester);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    final at = timeline.playheadMs;
    expect(timeline.motion, TimelineMotion.idle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(timeline.playheadMs, at, reason: 'the glide stopped');
    expect(video.asked, [at.round()], reason: 'waiting for the seek');

    video.slowSeek!.complete();
    video.slowSeek = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // On from the stop at the video's pace, not the glide's, and with no
    // seek to where the glide would have ended.
    expect(timeline.playheadMs, inInclusiveRange(at + 400, at + 700));
    expect(video.asked, [at.round(), 'play']);

    await landAndClose(tester, video);
  });

  testWidgets('a drag calls off a Play still waiting for its seek',
      (tester) async {
    final (video, _) = await openGliding(tester);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.drag(find.byType(ShotTimeline), const Offset(-60, 0));
    await tester.pump();

    video.slowSeek!.complete();
    video.slowSeek = null;
    await tester.pumpAndSettle();
    expect(video.asked, isNot(contains('play')));
    expect(find.byTooltip('Play'), findsOneWidget);

    await landAndClose(tester, video);
  });

  testWidgets(
      'going to the background calls off a Play still waiting for its seek',
      (tester) async {
    final (video, _) = await openGliding(tester);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    video.slowSeek!.complete();
    video.slowSeek = null;
    await tester.pumpAndSettle();
    expect(video.asked, isNot(contains('play')), reason: 'in the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(video.asked, isNot(contains('play')), reason: 'back in front');
    expect(find.byTooltip('Play'), findsOneWidget);

    await landAndClose(tester, video);
  });

  testWidgets('Back calls off a Play still waiting for its seek',
      (tester) async {
    // Nothing to save yet, so Back asks first and the editor stays.
    final (video, _) = await openGliding(tester, beep: false);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    video.slowSeek!.complete();
    video.slowSeek = null;
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    expect(video.asked, isNot(contains('play')));

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a seek that never lands keeps Play waiting a second at most',
      (tester) async {
    final (video, _) = await openGliding(tester);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 990));
    expect(video.asked, isNot(contains('play')));
    await tester.pump(const Duration(milliseconds: 20));
    // From wherever the video is: better than a Play that does nothing.
    expect(video.asked.last, 'play');
    expect(find.byTooltip('Pause'), findsOneWidget);

    await landAndClose(tester, video);
  });

  testWidgets('a seek that fails doesn\'t keep Play from playing',
      (tester) async {
    final (video, _) = await openGliding(tester);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    video.slowSeek!.completeError(PlatformException(code: 'seek'));
    video.slowSeek = null;
    await tester.pump();
    expect(video.asked.last, 'play');
    expect(find.byTooltip('Pause'), findsOneWidget);

    await landAndClose(tester, video);
  });

  testWidgets('Play at the end starts over once the seek there has landed',
      (tester) async {
    final platform = VideoPlayerPlatform.instance;
    final video = _PlayingVideo();
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = platform);
    await openEditor(tester);
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    timeline.centreOn(7000, animate: false);
    await tester.pump();
    video.slowSeek = Completer<void>();
    video.asked.clear();

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expect(timeline.playheadMs, 0);
    expect(video.asked, [0], reason: 'waiting for the seek');

    video.slowSeek!.complete();
    video.slowSeek = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Only seeks to the start, then play: at the end of the video, play()
    // itself would start over at 0 and add its own seek.
    expect(video.asked.last, 'play');
    expect(video.asked.whereType<int>().toSet(), {0});
    expect(timeline.playheadMs, inInclusiveRange(400, 700));

    await landAndClose(tester, video);
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

  testWidgets('a drag while the timeline glides to a shot starts at the shot',
      (tester) async {
    final state = await openEditor(tester);
    final shot = state().doc.activeShots[2];
    // Its row chooses it and glides the timeline there; the finger lands
    // a frame later.
    await tester.tap(find.byType(ShotBadge).at(2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(state().selectedId, shot.id);
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    expect(timeline.motion, TimelineMotion.settle, reason: 'still gliding');
    // Far enough to start the gesture: the shot moves 60 px later.
    await tester.drag(find.byType(ShotTimeline), const Offset(-60, 0));
    await tester.pumpAndSettle();
    final moved = 60 / timeline.pxPerSecond * 1000;
    // Give or take the snap to a nearby onset on release.
    expect(state().doc.shotById(shot.id)!.ms, closeTo(shot.ms + moved, 60));
  });

  testWidgets(
      'a drag moves a new shot until Done; after Done it scrolls past the shot',
      (tester) async {
    final state = await openEditor(tester);
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    const hint = 'Drag the timeline to move this shot.';
    expect(find.text('Done'), findsNothing);
    expect(find.text(hint), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Shot'));
    await tester.pumpAndSettle();
    final added = state().selected!;
    expect(added.ms, timeline.playheadMs.round());
    expect(find.text(hint), findsOneWidget);

    // Not placed yet: the shot rides along with the timeline.
    await tester.drag(find.byType(ShotTimeline), const Offset(-60, 0));
    await tester.pumpAndSettle();
    final placed = state().doc.shotById(added.id)!.ms;
    expect(placed, isNot(added.ms));
    expect(state().selectedId, added.id);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(state().selectedId, isNull);
    expect(state().doc.shotById(added.id)!.ms, placed);
    expect(find.text('Done'), findsNothing);
    expect(find.text(hint), findsNothing);

    // Placed: the same drag now scrolls, and the shot stays behind.
    final from = timeline.playheadMs;
    await tester.drag(find.byType(ShotTimeline), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(timeline.playheadMs, greaterThan(from + 100));
    expect(state().selectedId, isNull);
    expect(state().doc.shotById(added.id)!.ms, placed);
  });

  testWidgets('a shot chosen in the list gets Done and the hint too',
      (tester) async {
    final state = await openEditor(tester);
    await selectFirstShot(tester);
    final shot = state().selected!;
    expect(find.text('Drag the timeline to move this shot.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(state().selectedId, isNull);
    expect(state().doc.shotById(shot.id)!.ms, shot.ms);
    // Back to Set START and + Shot.
    expect(find.widgetWithText(FilledButton, 'Shot'), findsOneWidget);
  });

  /// A phone of [size] dp with a status bar and a 3-button navigation bar.
  const statusBar = 24.0, navigationBar = 48.0;
  Future<void> usePhone(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.padding =
        const FakeViewPadding(top: statusBar * 3, bottom: navigationBar * 3);
    tester.view.viewPadding = tester.view.padding;
    await tester.pumpAndSettle();
  }

  /// Where the video ends: its height plus the status bar's.
  double videoBottom(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EditorTransport)).dy;

  // By icon, so it reads the same in every language. Russian has the
  // tallest panel: its hint takes two lines.
  final addShot = find.widgetWithIcon(FilledButton, Icons.add);
  final done = find.widgetWithIcon(FilledButton, Icons.check);
  final export = find.widgetWithIcon(FilledButton, Icons.movie_outlined);

  /// The top of the video's foot, the timeline, the panel and the details:
  /// only the last may move when a shot is selected.
  List<double> tops(WidgetTester tester) => [
        videoBottom(tester),
        tester.getTopLeft(find.byType(ShotTimeline)).dy,
        tester.getTopLeft(find.byType(MarkerPanel).first).dy,
      ];
  double detailsHeight(WidgetTester tester) =>
      tester.getSize(find.byType(ListView).last).height;

  for (final (size, language) in const [
    (Size(360, 640), 'en'),
    (Size(360, 640), 'ru'),
    (Size(360, 690), 'ru'),
    (Size(360, 592), 'de'),
  ]) {
    testWidgets(
        'on a short screen ($size, $language) the video is smaller, Export '
        'stays on screen and nothing moves when a shot is selected',
        (tester) async {
      final state = await openEditor(tester, language: language);
      await usePhone(tester, size);
      final bottom = size.height - navigationBar;
      expect(tester.takeException(), isNull);
      expect(tester.getRect(export).bottom, lessThanOrEqualTo(bottom));
      // Smaller than 30 %, with its row of buttons (Back, the eye, the
      // menu) whole.
      final before = tops(tester);
      expect(before[0], lessThan(statusBar + size.height * 0.3));
      expect(before[0], greaterThanOrEqualTo(statusBar + 56));
      final list = detailsHeight(tester);

      // The panel of a selected shot is the tallest there is: the details
      // make the room for it, not the video.
      final shots = state().doc.shots.length;
      final lastShot = state().doc.lastShotId;
      final at = tester.getCenter(addShot);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, findsOneWidget);
      expect(tops(tester), before);
      expect(detailsHeight(tester), lessThan(list));
      expect(tester.getRect(export).bottom, lessThanOrEqualTo(bottom));
      // The panel's bottom is where the details begin, above Export.
      expect(tester.getRect(find.byType(MarkerPanel).first).bottom,
          lessThan(tester.getRect(export).top));

      // A second tap on the same spot finds Done there, not Last shot.
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(state().selectedId, isNull);
      expect(state().doc.shots, hasLength(shots + 1));
      expect(state().doc.lastShotId, lastShot);
      expect(tops(tester), before);
      expect(detailsHeight(tester), list);
    });
  }

  testWidgets('with room to spare the video keeps 30 % of the height',
      (tester) async {
    await openEditor(tester, language: 'ru');
    await usePhone(tester, const Size(360, 780));
    expect(videoBottom(tester), statusBar + 234);
    final before = tops(tester);
    await tester.tap(addShot);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tops(tester), before);
    expect(tester.getRect(export).bottom, 780 - navigationBar - 8);
  });

  testWidgets('with the keyboard up only the details show', (tester) async {
    await openEditor(tester);
    // A short screen, where the video has already given way: the room the
    // keyboard leaves would have it grow back while it is hidden.
    await usePhone(tester, const Size(360, 640));
    final video = tester.getSize(find.byType(ClipVideo, skipOffstage: false));
    // The list's own scrollable, not one inside a text field.
    final list = find
        .descendant(
            of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first;
    final details = tester.state(list);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ShotTimeline), findsNothing);
    expect(find.byType(MarkerPanel), findsNothing);
    expect(find.text('Export video'), findsNothing);
    // Off stage the video keeps its size: no resizing for the keyboard.
    expect(find.byType(ClipVideo), findsNothing);
    expect(tester.getSize(find.byType(ClipVideo, skipOffstage: false)), video);
    // The details are the same list (a new one would drop the keyboard),
    // from under the status bar down to the keyboard.
    expect(tester.state(list), same(details));
    expect(tester.getRect(find.byType(ListView).last),
        const Rect.fromLTRB(0, statusBar, 360, 640 - 300));
    // The list scrolls to the notes, above the keyboard.
    final notes = find.widgetWithText(TextField, 'Notes');
    await tester.dragUntilVisible(
        notes, find.byType(ListView).last, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getRect(notes).bottom, lessThanOrEqualTo(640 - 300));

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(ShotTimeline), findsOneWidget);
    expect(find.text('Export video'), findsOneWidget);
    expect(tester.getSize(find.byType(ClipVideo)), video);
    expect(tester.state(list), same(details));
  });

  testWidgets('Back asks first while there is nothing to save', (tester) async {
    await openEditor(tester, beep: false);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsNothing);
    // The system's Back (on Android, an edge swipe on the timeline) too.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('a Discard that fails says so, and Back still works',
      (tester) async {
    await openEditor(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(store.saved, hasLength(1));
    store.failDelete = true;
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this string?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('The string couldn’t be deleted. Try again.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Export waits while the string couldn\'t be saved',
      (tester) async {
    ExportPlan? exported;
    await openEditor(tester,
        overrides: exportToOverlay((plan) => exported = plan));
    store.failNext = true;
    await tester.tap(find.text('Export video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t save'), findsOneWidget);
    expect(exported, isNull);
    await tester.tap(find.text('Export anyway'));
    await tester.pumpAndSettle();
    expect(exported, isNotNull);
    expect(store.saved, isEmpty);
  });
}
