// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_check.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';

void main() {
  late Directory temp;
  late VideoWorkDir work;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('video_work_dir_test');
    work = VideoWorkDir(
      root: () async => Directory('${temp.path}/video_work'),
      cache: () async => Directory('${temp.path}/cache'),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  test('a session takes the picked copy away from the cache', () async {
    final picked = File('${temp.path}/cache/abc/clip.mp4')
      ..createSync(recursive: true)
      ..writeAsStringSync('video');
    final session = await work.createSession();
    final path = await session.adopt(picked.path);

    expect(picked.existsSync(), isFalse);
    expect(File(path).readAsStringSync(), 'video');
    expect(path, startsWith(session.dir.path));
    expect(session.clipPath, path);
  });

  test("a pick given up during the picker's copy leaves no copy behind",
      () async {
    final picked = File('${temp.path}/cache/abc/clip.mp4')
      ..createSync(recursive: true)
      ..writeAsStringSync('video');
    final session = await work.createSession();
    // Cancelled while the picker copied: the folder is gone when it returns.
    await session.dispose();

    await expectLater(session.adopt(picked.path), throwsA(anything));
    expect(picked.existsSync(), isFalse);
  });

  test('closing a session deletes its files, twice is fine', () async {
    final session = await work.createSession();
    File(session.pcmPath).writeAsStringSync('pcm');
    await session.dispose();
    await session.dispose();
    expect(session.dir.existsSync(), isFalse);
  });

  test('the sweep at app start removes every leftover session', () async {
    final a = await work.createSession();
    final b = await work.createSession();
    File(a.pcmPath).writeAsStringSync('pcm');
    await work.sweep();
    expect(a.dir.existsSync(), isFalse);
    expect(b.dir.existsSync(), isFalse);
    await work.sweep();
  });

  test('the sweep also removes copies the photo picker left in the cache',
      () async {
    final copy = File(
        '${temp.path}/cache/506b8b0f-c91a-4a9b-838c-1194a79dbd78/1000055609.mp4')
      ..createSync(recursive: true);
    final shares = Directory('${temp.path}/cache/share_plus')..createSync();
    final csv = File('${temp.path}/cache/string_42_1761220000000.csv')
      ..createSync();
    await work.sweep();
    expect(copy.parent.existsSync(), isFalse);
    expect(shares.existsSync(), isTrue);
    expect(csv.existsSync(), isTrue);
  });

  group('checking a clip', () {
    ClipInfo info({
      bool hasAudio = true,
      int durationMs = 30000,
      String? videoMime = 'video/hevc',
    }) =>
        ClipInfo(
            hasAudio: hasAudio, durationMs: durationMs, videoMime: videoMime);

    test('passes a normal clip', () => expect(checkClip(info()), isNull));
    test('names each problem', () {
      expect(checkClip(info(videoMime: null)), ClipProblem.unsupportedVideo);
      expect(checkClip(info(hasAudio: false)), ClipProblem.noSound);
      expect(checkClip(info(durationMs: 400)), ClipProblem.tooShort);
      // Long clips go through Choose the part instead.
      expect(checkClip(info(durationMs: 60 * 60 * 1000)), isNull);
    });
    test('knows slow motion and time-lapse by their capture rate', () {
      ClipInfo recorded(double capture, double playback) => ClipInfo(
            hasAudio: true,
            durationMs: 10000,
            videoMime: 'video/hevc',
            frameRate: playback,
            captureFrameRate: capture,
          );
      expect(checkClip(recorded(240, 30)), ClipProblem.slowMotion);
      expect(checkClip(recorded(4, 30)), ClipProblem.timeLapse);
      expect(checkClip(recorded(30, 30)), isNull);
      expect(checkClip(recorded(60, 59.94)), isNull);
    });

    test('maps every decoder error to a problem', () {
      expect(problemFor(ClipAudioError.noAudioTrack), ClipProblem.noSound);
      expect(problemFor(ClipAudioError.unsupportedCodec),
          ClipProblem.unreadableSound);
      expect(
          problemFor(ClipAudioError.decodeFailed), ClipProblem.unreadableSound);
      expect(problemFor(ClipAudioError.unsupportedFile),
          ClipProblem.unsupportedVideo);
      expect(problemFor(ClipAudioError.noSpace), ClipProblem.noSpace);
      expect(problemFor(ClipAudioError.unavailable), ClipProblem.failed);
      for (final e in ClipAudioError.values) {
        expect(problemFor(e), isA<ClipProblem>());
      }
    });
  });
}
