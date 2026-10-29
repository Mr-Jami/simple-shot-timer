// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_shot_finder.dart';
import 'package:simple_shot_timer/services/video/spectrogram.dart';
import 'package:simple_shot_timer/services/video/start_finder.dart';
import 'package:simple_shot_timer/services/video/tone_finder.dart';

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

    test('is the beep of a slow start, 8.3 s before the first shot', () {
      // Long-range steel: the shooter gets into position after the beep.
      final clip = syntheticClip(
        seconds: 13,
        shots: const [9.3, 10.5, 11.7],
        extra: (x) => addBeep(x, 1.0, 300),
      );
      expect(startOf(clip), closeTo(1.0, 0.005));
    });

    test('is empty when the first shot comes over 10 s after the beep', () {
      final clip = syntheticClip(
        seconds: 14,
        shots: const [11.2, 12.4],
        extra: (x) => addBeep(x, 1.0, 300),
      );
      expect(startOf(clip), isNull);
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

  group('the clicks of a piezo beep', () {
    const fps = 374.67;
    ToneRun beep(double onset, double end) => ToneRun(
          startFrame: (onset * fps).round(),
          endFrame: (end * fps).round() - 1,
          frequencyHz: 3000,
          onsetSeconds: onset,
          framesPerSecond: fps,
        );

    test('a click just before the onset does not disqualify the beep', () {
      final tone = beep(1.0, 1.4);
      expect(chooseStart([tone], [0.985, 2.2, 2.6]), same(tone));
    });

    test('a real shot shortly before a tone still disqualifies it', () {
      expect(chooseStart([beep(1.0, 1.4)], [0.9, 2.2, 2.6]), isNull);
    });

    test('a beep whose only "shot" is its own stop click is not START', () {
      expect(chooseStart([beep(1.0, 1.4)], [1.42]), isNull);
    });

    test('the click as the START beep stops is not a shot of the string', () {
      final spectrogram =
          Spectrogram.compute(Int16List(clipSampleRate * 7), clipSampleRate);
      final rate = spectrogram.framesPerSecond;
      final tone = ToneRun(
        startFrame: (0.505 * rate).round(),
        endFrame: (0.934 * rate).round() - 1,
        frequencyHz: 3000,
        onsetSeconds: 0.505,
        framesPerSecond: rate,
      );
      final analysis = ClipAnalysis(
        spectrogram: spectrogram,
        tones: [tone],
        scan: ShotScan(shots: [
          for (final t in [0.963, 1.251, 2.036]) ShotHit((t * rate).round()),
        ], gate: 0),
        sensitivity: ShotSensitivity.normal,
      );
      expect(analysis.start, same(tone));
      expect(analysis.stringShotSeconds, hasLength(2));
      expect(analysis.stringShotSeconds.first, closeTo(1.251, 0.003));
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

  for (final samples in [0, 100]) {
    test('a clip with $samples samples has no START and no shots', () {
      final analysis = analyzePcm(Int16List(samples), clipSampleRate);
      expect(analysis.startSeconds, isNull);
      expect(analysis.shotSeconds, isEmpty);
    });
  }

  test('a muted sound track is silent; faint noise and a range clip are not',
      () {
    Spectrogram of(Int16List pcm) => Spectrogram.compute(pcm, clipSampleRate);
    Int16List noise(int amplitude) {
      final random = math.Random(1);
      return Int16List.fromList([
        for (var i = 0; i < clipSampleRate * 2; i++)
          random.nextInt(2 * amplitude + 1) - amplitude,
      ]);
    }

    expect(of(Int16List(clipSampleRate * 2)).isSilent, isTrue);
    // The decoder's rounding on a muted track.
    expect(of(noise(3)).isSilent, isTrue);
    expect(of(noise(10)).isSilent, isFalse);
    expect(of(syntheticClip()).isSilent, isFalse);
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
