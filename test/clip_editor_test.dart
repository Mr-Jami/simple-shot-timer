// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/clip_editor_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer_runner.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/video_string_store.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';

import 'clip_fixtures.dart';

class _MemoryStore implements VideoStringStore {
  final inserted = <TimerString>[];
  final updated = <TimerString>[];
  final deleted = <int>[];
  var failNext = false;
  Duration writeTime = Duration.zero;

  @override
  Future<TimerString> insertString(TimerString s,
      {required int historyCap}) async {
    if (writeTime > Duration.zero) await Future<void>.delayed(writeTime);
    if (failNext) {
      failNext = false;
      throw Exception('disk full');
    }
    inserted.add(s);
    return s.copyWith(id: 41 + inserted.length);
  }

  @override
  Future<void> updateVideoString(TimerString s) async {
    if (writeTime > Duration.zero) await Future<void>.delayed(writeTime);
    updated.add(s);
  }

  @override
  Future<void> deleteString(int id) async => deleted.add(id);
}

class _FakeSession extends VideoSession {
  _FakeSession() : super(Directory('session'));

  var disposed = false;

  @override
  Future<void> dispose() async => disposed = true;
}

class _SlowAnalyzer implements ClipAnalyzerRunner {
  final delays = <ShotSensitivity, Duration>{};

  @override
  Future<ClipAnalysis> analyze(String pcmPath, int sampleRate) =>
      throw UnimplementedError();

  @override
  Future<ClipAnalysis> resense(ClipAnalysis a, ShotSensitivity s) async {
    await Future<void>.delayed(delays[s] ?? Duration.zero);
    return a.withSensitivity(s);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final withBeep = analyzePcm(
    syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
    clipSampleRate,
  );
  final noBeep = analyzePcm(syntheticClip(), clipSampleRate);
  final recorded = DateTime.utc(2026, 10, 20, 9, 15, 30);
  final importedAt = DateTime(2026, 10, 23, 14);

  late SharedPreferences prefs;
  late _MemoryStore store;
  late _SlowAnalyzer analyzer;
  late _FakeSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = _MemoryStore();
    analyzer = _SlowAnalyzer();
    session = _FakeSession();
  });

  ClipEditorArgs args(ClipAnalysis analysis, {TimerString? saved}) =>
      ClipEditorArgs(
        clip: AnalyzedClip(
          info: ClipInfo(
            hasAudio: true,
            durationMs: 7000,
            videoMime: 'video/hevc',
            creationTime: recorded,
          ),
          analysis: analysis,
          audioOriginMs: 0,
        ),
        session: session,
        importedAt: importedAt,
        saved: saved,
      );

  /// Runs [script] against an editor on a fake clock.
  void run(
    ClipEditorArgs a,
    void Function(FakeAsync async, ClipEditorNotifier editor,
            ClipEditorState Function() state)
        script,
  ) {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        videoStringStoreProvider.overrideWithValue(store),
        clipAnalyzerProvider.overrideWithValue(analyzer),
      ]);
      final sub = container.listen(clipEditorProvider(a), (_, __) {});
      script(
        async,
        container.read(clipEditorProvider(a).notifier),
        () => container.read(clipEditorProvider(a)),
      );
      sub.close();
      container.dispose();
      async.flushMicrotasks();
    });
  }

  group('saving', () {
    test('leaving without START saves nothing', () {
      run(args(noBeep), (async, editor, state) {
        expect(state().doc.startMs, isNull);
        editor.flush();
        async.flushMicrotasks();
        expect(store.inserted, isEmpty);
      });
    });

    test('leaving with START and shots saves the string once', () {
      run(args(withBeep), (async, editor, state) {
        editor.flush();
        editor.flush();
        async.flushMicrotasks();
        final s = store.inserted.single;
        expect(s.isVideo, isTrue);
        expect(s.drillMode, DrillMode.standard);
        expect(s.createdAt, importedAt);
        expect(s.videoStartMs, closeTo(1000, 5));
        expect(s.videoDurationMs, 7000);
        expect(s.videoRecordedAt, recorded);
        expect(s.shots.map((x) => x.timeMs / 1000),
            [for (final t in referenceShotTimes) closeTo(t - 1, 0.006)]);
        expect(state().saveStatus, SaveStatus.saved);
        expect(state().savedId, 42);
      });
    });

    test('after the first save, edits autosave once they settle', () {
      run(args(withBeep), (async, editor, state) {
        editor.flush();
        async.flushMicrotasks();
        editor.setLabel('Bill drill');
        async.elapse(const Duration(milliseconds: 300));
        editor.addShot(6000);
        async.elapse(const Duration(milliseconds: 300));
        expect(store.updated, isEmpty);
        async.elapse(const Duration(milliseconds: 400));
        final s = store.updated.single;
        expect(s.id, 42);
        expect(s.label, 'Bill drill');
        expect(s.shots.last.manual, isTrue);
      });
    });

    test('an edit during a write is saved by the next one', () {
      store.writeTime = const Duration(milliseconds: 200);
      run(args(withBeep), (async, editor, state) {
        editor.flush();
        async.elapse(const Duration(milliseconds: 100));
        editor.setNotes('slow draw');
        async.elapse(const Duration(milliseconds: 150));
        expect(state().saveStatus, SaveStatus.unsaved);
        async.elapse(const Duration(seconds: 1));
        expect(store.updated.single.notes, 'slow draw');
        expect(state().saveStatus, SaveStatus.saved);
      });
    });

    test('a failed save is retried on the next flush', () {
      store.failNext = true;
      run(args(withBeep), (async, editor, state) {
        editor.flush();
        async.flushMicrotasks();
        expect(state().saveStatus, SaveStatus.failed);
        editor.flush();
        async.flushMicrotasks();
        expect(store.inserted, hasLength(1));
        expect(state().saveStatus, SaveStatus.saved);
      });
    });

    test('Discard deletes the saved string and stops saving', () {
      run(args(withBeep), (async, editor, state) {
        editor.flush();
        async.flushMicrotasks();
        editor.addShot(6000);
        editor.discard();
        async.elapse(const Duration(seconds: 1));
        expect(store.deleted, [42]);
        expect(store.updated, isEmpty);
      });
    });

    test('closing the editor deletes the clip\'s folder', () {
      run(args(withBeep), (async, editor, state) {});
      expect(session.disposed, isTrue);
    });
  });

  group('editing', () {
    test('deleting a shot can be undone', () {
      run(args(withBeep), (async, editor, state) {
        final id = state().doc.activeShots[1].id;
        editor.select(id);
        editor.deleteShot(id);
        expect(state().doc.activeShots, hasLength(4));
        expect(state().selectedId, isNull);
        expect(state().canUndo, isTrue);
        editor.undo();
        expect(state().doc.activeShots, hasLength(5));
        expect(state().canUndo, isFalse);
      });
    });

    test('an added shot is selected and nudges by a millisecond', () {
      run(args(withBeep), (async, editor, state) {
        editor.addShot(6000);
        final id = state().selectedId!;
        editor.nudge(id, 1);
        expect(state().selected!.ms, 6001);
      });
    });

    test('a new sensitivity keeps edits, and the latest choice wins', () {
      analyzer.delays[ShotSensitivity.fewer] = const Duration(seconds: 2);
      run(args(withBeep), (async, editor, state) {
        final deleted = state().doc.activeShots.first;
        editor.deleteShot(deleted.id);
        editor.addShot(6000);
        editor.setSensitivity(ShotSensitivity.fewer);
        editor.setSensitivity(ShotSensitivity.more);
        async.elapse(const Duration(seconds: 3));
        expect(state().sensitivity, ShotSensitivity.more);
        expect(state().sensitivityBusy, isFalse);
        final times = [for (final s in state().doc.activeShots) s.ms];
        expect(times, isNot(contains(deleted.ms)));
        expect(times, contains(6000));
      });
    });
  });

  test('a reopened string shows its saved markers and updates it', () {
    final saved = TimerString(
      id: 7,
      createdAt: DateTime(2026, 10, 21),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [Shot(index: 0, timeMs: 1500, manual: true)],
      label: 'Bill drill',
      source: StringSource.video,
      videoStartMs: 1000,
    );
    run(args(withBeep, saved: saved), (async, editor, state) {
      expect(state().reopened, isTrue);
      expect([for (final s in state().doc.activeShots) s.ms], [2500]);
      editor.setSensitivity(ShotSensitivity.more);
      async.flushMicrotasks();
      expect(state().doc.activeShots, hasLength(1));
      editor.flush();
      async.flushMicrotasks();
      expect(store.updated, isEmpty, reason: 'nothing changed');
      editor.addShot(3000);
      editor.flush();
      async.flushMicrotasks();
      expect(store.inserted, isEmpty);
      expect(store.updated.single.id, 7);
      expect(store.updated.single.label, 'Bill drill');
    });
  });
}
