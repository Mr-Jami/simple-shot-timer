// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/video_import_provider.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/screens/video_import_screen.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer_runner.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_check.dart';
import 'package:simple_shot_timer/services/video/clip_picker.dart';
import 'package:simple_shot_timer/services/video/part_window.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';

import 'clip_fixtures.dart';

/// No real files: sessions only record what happened to them.
class _FakeSession extends VideoSession {
  _FakeSession() : super(Directory('session'));

  var disposed = false;
  var pcmDeleted = false;

  @override
  Future<String> adopt(String pickedPath) async => pickedPath;

  @override
  Future<void> deletePcm() async => pcmDeleted = true;

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeWorkDir extends VideoWorkDir {
  final sessions = <_FakeSession>[];
  Duration createTime = Duration.zero;

  @override
  Future<VideoSession> createSession() async {
    await Future<void>.delayed(createTime);
    return _FakeSession()..also(sessions.add);
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

class _FakePicker implements ClipPicker {
  String? path = 'session/clip.mp4';
  ClipAudioException? error;

  /// A Files pick copying for this long, reporting every 100 ms.
  Duration copyTime = Duration.zero;
  CancelToken? lastCancel;

  @override
  Future<String?> pick(
    ClipSource source,
    VideoSession session, {
    void Function(double fraction)? onCopyProgress,
    CancelToken? cancel,
  }) async {
    lastCancel = cancel;
    for (var t = Duration.zero; t < copyTime; t += _copyStep) {
      onCopyProgress?.call(t.inMilliseconds / copyTime.inMilliseconds);
      await Future<void>.delayed(_copyStep);
    }
    if (error != null) throw error!;
    return path;
  }
}

const _copyStep = Duration(milliseconds: 100);

class _FakeAudio implements ClipAudioSource {
  ClipInfo info = const ClipInfo(
    hasAudio: true,
    durationMs: 7000,
    videoMime: 'video/hevc',
  );
  Duration decodeTime = const Duration(milliseconds: 100);
  ClipAudioError? decodeError;
  var probes = 0;
  var decodes = 0;
  CancelToken? lastCancel;
  (int, int?)? lastWindow;

  /// The loudness scan: these values, in two batches 1 s apart.
  List<double> loudness = const [];
  CancelToken? scanCancel;
  var thumbnailCalls = 0;

  @override
  Future<ClipInfo> probe(String path) async {
    probes++;
    return info;
  }

  @override
  Future<DecodedAudio> decode(
    String path, {
    required String outputPath,
    int startMs = 0,
    int? endMs,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) {
    decodes++;
    lastCancel = cancel;
    lastWindow = (startMs, endMs);
    final done = Completer<DecodedAudio>();
    final timer = Timer(decodeTime, () {
      if (decodeError != null) {
        done.completeError(ClipAudioException(decodeError!));
      } else {
        done.complete(DecodedAudio(
          pcmPath: outputPath,
          sampleRate: clipSampleRate,
          channelCount: 1,
          sampleCount: clipSampleRate * 7,
          firstSampleTimeUs: startMs * 1000 + 20000,
        ));
      }
    });
    cancel?.whenCancelled.then((_) {
      timer.cancel();
      if (!done.isCompleted) {
        done.completeError(const ClipAudioException(ClipAudioError.cancelled));
      }
    });
    return done.future;
  }

  @override
  Future<int> scanLoudness(
    String path, {
    int bucketMs = 250,
    required void Function(int from, List<double> values) onValues,
    CancelToken? cancel,
  }) async {
    scanCancel = cancel;
    final half = loudness.length ~/ 2;
    for (final (from, to) in [(0, half), (half, loudness.length)]) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (cancel?.isCancelled ?? false) {
        throw const ClipAudioException(ClipAudioError.cancelled);
      }
      onValues(from, loudness.sublist(from, to));
    }
    return loudness.length;
  }

  @override
  Future<void> thumbnails(
    String path, {
    required List<int> timesMs,
    int width = 160,
    required void Function(int index, Uint8List jpeg) onFrame,
    CancelToken? cancel,
  }) async {
    thumbnailCalls++;
    for (var i = 0; i < timesMs.length; i++) {
      onFrame(i, Uint8List(1));
    }
  }
}

class _FakeAnalyzer implements ClipAnalyzerRunner {
  _FakeAnalyzer(this.result);

  ClipAnalysis result;
  Duration time = const Duration(milliseconds: 50);
  var runs = 0;

  @override
  Future<ClipAnalysis> analyze(String pcmPath, int sampleRate) async {
    runs++;
    await Future<void>.delayed(time);
    return result;
  }

  @override
  Future<ClipAnalysis> resense(ClipAnalysis a, ShotSensitivity s) async =>
      a.withSensitivity(s);
}

void main() {
  final analysis = analyzePcm(
    syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
    clipSampleRate,
  );

  late _FakeWorkDir work;
  late _FakePicker picker;
  late _FakeAudio audio;
  late _FakeAnalyzer analyzer;

  setUp(() {
    work = _FakeWorkDir();
    picker = _FakePicker();
    audio = _FakeAudio();
    analyzer = _FakeAnalyzer(analysis);
  });

  /// Runs an import on a fake clock; [script] gets the container and the
  /// states seen so far.
  void run(
      void Function(
              FakeAsync async, ProviderContainer c, List<ImportState> seen)
          script,
      {TimerString? reopen}) {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        videoWorkDirProvider.overrideWithValue(work),
        clipPickerProvider.overrideWithValue(picker),
        clipAudioSourceProvider.overrideWithValue(audio),
        clipAnalyzerProvider.overrideWithValue(analyzer),
      ]);
      final seen = <ImportState>[];
      container.listen(videoImportProvider(0), (_, next) => seen.add(next),
          fireImmediately: true);
      container
          .read(videoImportProvider(0).notifier)
          .start(ClipSource.photos, reopen: reopen);
      script(async, container, seen);
      container.dispose();
      async.flushMicrotasks();
    });
  }

  bool everVisible(List<ImportState> seen) =>
      seen.any((s) => s is ImportWorking && s.visible);

  test('a quick import goes straight to the editor', () {
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 200));
      final ready = seen.last as ImportReady;
      expect(everVisible(seen), isFalse);
      // The decoder's first sample sits 20 ms into the clip.
      expect(ready.clip.startMs, closeTo(1020, 5));
      expect(work.sessions.single.pcmDeleted, isTrue);
      expect(work.sessions.single.disposed, isFalse);
    });
  });

  test('a slow import shows Analyzing and keeps it up long enough', () {
    audio.decodeTime = const Duration(milliseconds: 400);
    analyzer.time = Duration.zero;
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 350));
      expect((seen.last as ImportWorking).visible, isTrue);
      async.elapse(const Duration(milliseconds: 400));
      // Work ended at 400 ms, but the view appeared at 300 ms.
      expect(seen.last, isA<ImportWorking>());
      async.elapse(const Duration(milliseconds: 100));
      expect(seen.last, isA<ImportReady>());
    });
  });

  test('a Files copy that takes a while shows Analyzing with its progress', () {
    picker.copyTime = const Duration(seconds: 1);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 450));
      final working = seen.last as ImportWorking;
      expect(working.visible, isTrue);
      expect(working.step, ImportStep.reading);
      expect(working.progress, closeTo(0.4, 0.01));
      async.elapse(const Duration(seconds: 1));
      expect(seen.last, isA<ImportReady>());
    });
  });

  test('Cancel during a Files copy stops it and deletes the folder', () {
    picker.copyTime = const Duration(seconds: 2);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 500));
      c.read(videoImportProvider(0).notifier).cancel();
      async.elapse(const Duration(seconds: 3));
      expect(picker.lastCancel!.isCancelled, isTrue);
      expect(seen.last, isA<ImportCancelled>());
      expect(audio.probes, 0);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('leaving while the work folder is made deletes it once made', () {
    work.createTime = const Duration(milliseconds: 100);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 50));
      c.dispose();
      async.elapse(const Duration(milliseconds: 100));
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('backing out of the picker deletes the folder', () {
    picker.path = null;
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 10));
      expect(seen.last, isA<ImportCancelled>());
      expect(audio.probes, 0);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('a clip without sound is named before any decoding', () {
    audio.info = const ClipInfo(
      hasAudio: false,
      durationMs: 7000,
      videoMime: 'video/hevc',
    );
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 10));
      expect((seen.last as ImportProblem).problem, ClipProblem.noSound);
      expect(audio.decodes, 0);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('a sound track with nothing in it is named once decoded', () {
    analyzer.result = analyzePcm(Int16List(clipSampleRate * 7), clipSampleRate);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 500));
      expect((seen.last as ImportProblem).problem, ClipProblem.noSound);
      expect(analyzer.runs, 1);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('a sound the phone cannot decode has its own message', () {
    audio.decodeError = ClipAudioError.unsupportedCodec;
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 200));
      expect((seen.last as ImportProblem).problem, ClipProblem.unreadableSound);
      expect(analyzer.runs, 0);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  test('Cancel stops the decode and deletes the folder', () {
    audio.decodeTime = const Duration(seconds: 5);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 500));
      c.read(videoImportProvider(0).notifier).cancel();
      async.elapse(const Duration(seconds: 6));
      expect(audio.lastCancel!.isCancelled, isTrue);
      expect(seen.last, isA<ImportCancelled>());
      expect(analyzer.runs, 0);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  group('a clip over three minutes', () {
    const tenMinutes = 10 * 60 * 1000;
    // Quiet, with a loud burst from 6:00 to 6:30 (250 ms buckets).
    final loud = [
      for (var i = 0; i < tenMinutes ~/ 250; i++)
        i >= 1440 && i < 1560 ? 0.5 : 0.01,
    ];

    setUp(() {
      audio.info = const ClipInfo(
        hasAudio: true,
        durationMs: tenMinutes,
        videoMime: 'video/hevc',
      );
      audio.loudness = loud;
    });

    test('opens Choose the part and fills it in as the scan goes', () {
      run((async, c, seen) {
        async.elapse(const Duration(milliseconds: 10));
        var part = seen.last as ImportChoosePart;
        expect(part.window, const PartWindow(0, maxClipPartMs));
        expect(part.thumbnails.every((t) => t != null), isTrue);
        expect(audio.decodes, 0);

        async.elapse(const Duration(seconds: 1));
        part = seen.last as ImportChoosePart;
        expect(part.loudness, hasLength(loud.length ~/ 2));
        expect(part.scanned, isFalse);

        async.elapse(const Duration(seconds: 1));
        part = seen.last as ImportChoosePart;
        expect(part.loudness, hasLength(loud.length));
        expect(part.scanned, isTrue);
        // Placed on the loudest three minutes, which hold the burst.
        expect(part.window.startMs, lessThanOrEqualTo(6 * 60 * 1000));
        expect(part.window.endMs, greaterThanOrEqualTo(6 * 60 * 1000 + 30000));
        expect(part.window.lengthMs, maxClipPartMs);
      });
    });

    test('a window the user moved stays where they put it', () {
      run((async, c, seen) {
        async.elapse(const Duration(milliseconds: 10));
        const mine = PartWindow(30000, 90000);
        c.read(videoImportProvider(0).notifier).moveWindow(mine);
        async.elapse(const Duration(seconds: 3));
        final part = seen.last as ImportChoosePart;
        expect(part.scanned, isTrue);
        expect(part.window, mine);
      });
    });

    test('Analyze this part stops the scan and analyses only the window', () {
      run((async, c, seen) {
        async.elapse(const Duration(milliseconds: 10));
        const mine = PartWindow(30000, 90000);
        final import = c.read(videoImportProvider(0).notifier);
        import.moveWindow(mine);
        import.analysePart();
        async.flushMicrotasks();
        expect(audio.scanCancel!.isCancelled, isTrue);
        // Analyzing shows at once: the user just asked for it.
        expect((seen.last as ImportWorking).visible, isTrue);
        expect(audio.lastWindow, (30000, 90000));

        async.elapse(const Duration(milliseconds: 600));
        final ready = seen.last as ImportReady;
        expect(ready.clip.part, mine);
        expect((ready.clip.fromMs, ready.clip.toMs), (30000, 90000));
        // Clip time: the beep is 1 s into the decoded window.
        expect(ready.clip.startMs, closeTo(31020, 5));
        expect(ready.clip.toDoc().fromMs, 30000);
      });
    });

    test('reopening a saved string analyses the part around it', () {
      final saved = TimerString(
        createdAt: DateTime(2026, 10, 21),
        drillMode: DrillMode.standard,
        delayMode: DelayMode.instant,
        delayUsedMs: 0,
        pars: const [],
        shots: [Shot(index: 0, timeMs: 1500), Shot(index: 1, timeMs: 4000)],
        source: StringSource.video,
        videoStartMs: 400000,
      );
      run(reopen: saved, (async, c, seen) {
        async.elapse(const Duration(milliseconds: 200));
        expect(seen.whereType<ImportChoosePart>(), isEmpty);
        expect(audio.thumbnailCalls, 0);
        final part = (seen.last as ImportReady).clip.part!;
        expect(part.lengthMs, maxClipPartMs);
        expect(part.startMs, lessThan(400000));
        expect(part.endMs, greaterThan(404000));
      });
    });

    test('closing it stops the scan and deletes the folder', () {
      run((async, c, seen) {
        async.elapse(const Duration(milliseconds: 10));
        c.read(videoImportProvider(0).notifier).cancel();
        async.flushMicrotasks();
        expect(seen.last, isA<ImportCancelled>());
        expect(audio.scanCancel!.isCancelled, isTrue);
        expect(work.sessions.single.disposed, isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(seen.last, isA<ImportCancelled>());
      });
    });
  });

  test('leaving the screen mid-import cleans up too', () {
    audio.decodeTime = const Duration(seconds: 5);
    run((async, c, seen) {
      async.elapse(const Duration(milliseconds: 500));
      c.dispose();
      async.flushMicrotasks();
      expect(audio.lastCancel!.isCancelled, isTrue);
      expect(work.sessions.single.disposed, isTrue);
    });
  });

  testWidgets('Choose another after a problem starts a new import',
      (tester) async {
    // rootBundle caches each string as a future owned by the test that
    // loaded it.
    rootBundle.clear();
    audio.info = const ClipInfo(
      hasAudio: false,
      durationMs: 7000,
      videoMime: 'video/hevc',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        videoWorkDirProvider.overrideWithValue(work),
        clipPickerProvider.overrideWithValue(picker),
        clipAudioSourceProvider.overrideWithValue(audio),
        clipAnalyzerProvider.overrideWithValue(analyzer),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: VideoImportScreen(source: ClipSource.photos),
      ),
    ));
    final noSound = find.textContaining('has no sound');
    // AppLocalizations reads its JSON from the asset bundle: real I/O. The
    // import's own timers run on the test clock.
    for (var i = 0; noSound.evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(noSound, findsOneWidget);

    audio.info = const ClipInfo(
      hasAudio: true,
      durationMs: 400,
      videoMime: 'video/hevc',
    );
    await tester.tap(find.text('Choose another video'));
    await tester.pumpAndSettle();
    // The second clip was picked and checked, not dropped.
    expect(find.textContaining('too short'), findsOneWidget);
    expect(audio.probes, 2);
    expect(work.sessions, hasLength(2));
    expect(work.sessions.every((s) => s.disposed), isTrue);
  });
}
