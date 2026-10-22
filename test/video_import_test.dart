// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/providers/video_import_provider.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer_runner.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_check.dart';
import 'package:simple_shot_timer/services/video/clip_picker.dart';
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

  @override
  Future<VideoSession> createSession() async =>
      _FakeSession()..also(sessions.add);
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

  @override
  Future<String?> pick(
    ClipSource source,
    VideoSession session, {
    void Function(double fraction)? onCopyProgress,
  }) async {
    if (error != null) throw error!;
    return path;
  }
}

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

  @override
  Future<ClipInfo> probe(String path) async {
    probes++;
    return info;
  }

  @override
  Future<DecodedAudio> decode(
    String path, {
    required String outputPath,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) {
    decodes++;
    lastCancel = cancel;
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
          firstSampleTimeUs: 20000,
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
}

class _FakeAnalyzer implements ClipAnalyzerRunner {
  _FakeAnalyzer(this.result);

  final ClipAnalysis result;
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
          script) {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        videoWorkDirProvider.overrideWithValue(work),
        clipPickerProvider.overrideWithValue(picker),
        clipAudioSourceProvider.overrideWithValue(audio),
        clipAnalyzerProvider.overrideWithValue(analyzer),
      ]);
      final seen = <ImportState>[];
      container.listen(videoImportProvider, (_, next) => seen.add(next),
          fireImmediately: true);
      container.read(videoImportProvider.notifier).start(ClipSource.photos);
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
      c.read(videoImportProvider.notifier).cancel();
      async.elapse(const Duration(seconds: 6));
      expect(audio.lastCancel!.isCancelled, isTrue);
      expect(seen.last, isA<ImportCancelled>());
      expect(analyzer.runs, 0);
      expect(work.sessions.single.disposed, isTrue);
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
}
