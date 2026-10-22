// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';

import 'clip_fixtures.dart';

double? startOf(Int16List clip) => analyzePcm(clip, clipSampleRate).startSeconds;

void main() {
  group('START', () {
    test('is the beep of the reference clip, with the same splits', () {
      final analysis = analyzePcm(referenceClip(), clipSampleRate);
      expect(analysis.startSeconds, closeTo(1.0, 0.005));
      final times = [analysis.startSeconds!, ...analysis.stringShotSeconds];
      final splits = [
        for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
      ];
      expect(splits.map((s) => (s * 100).round() / 100),
          [1.2, 0.42, 0.33, 0.35, 0.8]);
    });

    test('is the 300 ms start beep of this app', () {
      final clip = syntheticClip(extra: (x) => addBeep(x, 1.0, 300));
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('is the start beep, not a later 700 ms par beep', () {
      // The reference takes the longer par beep here, then falls back to 0 s
      // because no shot follows it.
      final clip = syntheticClip(extra: (x) {
        addBeep(x, 1.0, 300);
        addBeep(x, 4.8, 700);
      });
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('is the start beep when the last shot lands on the par beep', () {
      final clip = syntheticClip(extra: (x) {
        addBeep(x, 1.0, 300);
        addBeep(x, 4.0, 700);
      });
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('finds a beep filmed from a distance (20 dB quieter)', () {
      final clip = syntheticClip(extra: (x) => addBeep(x, 1.0, 300, gain: 0.1));
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    for (final ms in [100, 200, 500, 1000, 2000]) {
      test('finds a $ms ms beep from another timer', () {
        final clip = syntheticClip(
          seconds: 8,
          shots: const [3.2, 3.62, 3.95, 4.3, 5.1],
          extra: (x) => addBeep(x, 1.0, ms, frequencyHz: 3100),
        );
        expect(startOf(clip), closeTo(1.0, 0.005));
      });
    }

    test('takes the first pulse of a double beep', () {
      final clip = syntheticClip(extra: (x) {
        addBeep(x, 1.0, 150, frequencyHz: 2800);
        addBeep(x, 1.25, 150, frequencyHz: 2800);
      });
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('is the real beep, not the button chirps before it', () {
      final clip = syntheticClip(extra: (x) {
        addBeep(x, 0.2, 150, frequencyHz: 2000);
        addBeep(x, 0.5, 150, frequencyHz: 2000);
        addBeep(x, 1.0, 300);
      });
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('is empty, not 0 s, when there is no beep', () {
      final analysis = analyzePcm(syntheticClip(), clipSampleRate);
      expect(analysis.startSeconds, isNull);
      expect(analysis.shotSeconds, hasLength(5));
      expect(analysis.stringShotSeconds, isEmpty);
    });

    test('is never steel ringing after a hit', () {
      final clip = syntheticClip(
        extra: (x) => addBeep(x, 2.67, 600, frequencyHz: 1500, gain: 0.5),
      );
      expect(startOf(clip), isNull);
    });
  });

  test('finds a shot fired while a long beep still sounds', () {
    final clip = syntheticClip(
      shots: const [1.6, 2.0, 2.4],
      extra: (x) => addBeep(x, 1.0, 2000, frequencyHz: 3100),
    );
    final analysis = analyzePcm(clip, clipSampleRate);
    expect(analysis.startSeconds, closeTo(1.0, 0.005));
    expect(analysis.stringShotSeconds, hasLength(3));
    expect(analysis.stringShotSeconds.first, closeTo(1.6, 0.005));
  });

  test('changing sensitivity reuses the analysis and keeps START', () {
    final analysis = analyzePcm(
      syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
      clipSampleRate,
    );
    final fewer = analysis.withSensitivity(ShotSensitivity.fewer);
    expect(fewer.sensitivity, ShotSensitivity.fewer);
    expect(fewer.scan.gate, greaterThan(analysis.scan.gate));
    expect(fewer.startSeconds, analysis.startSeconds);
    expect(identical(fewer.spectrogram, analysis.spectrogram), isTrue);
  });

  test('analyses the raw PCM file the decoder writes', () async {
    final clip = syntheticClip(extra: (x) => addBeep(x, 1.0, 300));
    final dir = await Directory.systemTemp.createTemp('clip_analyzer_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/clip.pcm');
    await file.writeAsBytes(clip.buffer.asUint8List());

    final fromFile = await analyzePcmFile(file.path, clipSampleRate);
    final direct = analyzePcm(clip, clipSampleRate);
    expect(fromFile.startSeconds, direct.startSeconds);
    expect(fromFile.shotSeconds, direct.shotSeconds);
  });
}
