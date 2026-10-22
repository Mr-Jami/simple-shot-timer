// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_shot_finder.dart';
import 'package:simple_shot_timer/services/video/spectrogram.dart';

import 'clip_fixtures.dart';

void main() {
  // Expected values come from video-shot-timer/src/shot-detector.mjs run on
  // the same signal (its test/synthetic.wav).
  group('parity with the reference detector', () {
    final spectrogram = Spectrogram.compute(referenceClip(), clipSampleRate);

    test('frames the clip the same way', () {
      expect(spectrogram.frameCount, 2248);
      expect(spectrogram.framesPerSecond, closeTo(374.6667, 1e-3));
    });

    test('produces the same spectrogram values', () {
      const spots = [
        [0, 0, 52],
        [100, 20, 77],
        [375, 15, 205],
        [380, 16, 216],
        [824, 3, 193],
        [825, 40, 191],
        [1000, 127, 134],
      ];
      for (final s in spots) {
        expect(spectrogram.value(s[0], s[1]), closeTo(s[2], 1),
            reason: 'frame ${s[0]}, bin ${s[1]}');
      }
    });

    test('finds the same shots on the same frames with the same gate', () {
      final scan = findShots(spectrogram);
      expect(scan.shots.map((s) => s.frame), [824, 982, 1105, 1237, 1537]);
      expect(scan.gate, closeTo(152.6005, 0.01));
    });
  });

  group('spectrogram scale', () {
    test('clamps magnitudes near full scale instead of wrapping to silence',
        () {
      // The reference wraps these to 0, which reads as silence.
      expect(Spectrogram.byteFor(0.99), 255);
      expect(Spectrogram.byteFor(1.5), 255);
    });

    test('keeps the reference scale below that', () {
      // 256 + trunc(45·log10(m)): 0.1 → -45 → 211, 1e-3 → -135 → 121.
      expect(Spectrogram.byteFor(0.1), 211);
      expect(Spectrogram.byteFor(1e-3), 121);
      expect(Spectrogram.byteFor(0), 1);
    });
  });

  group('shots the reference test misses', () {
    List<ShotHit> shotsIn(Int16List clip, {bool softOnsets = true}) =>
        findShots(Spectrogram.compute(clip, clipSampleRate),
                softOnsets: softOnsets)
            .shots;

    test('finds shots that hold their level instead of decaying', () {
      // How a phone camera with automatic gain control records a shot. The
      // reference test wants the sound to decay within 100 ms.
      final clip = syntheticClip(shot: addHeldBurst);
      expect(shotsIn(clip, softOnsets: false).length, lessThan(3));
      final shots = shotsIn(clip);
      expect(shots, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(shots[i].frame / 374.67, closeTo(referenceShotTimes[i], 0.01));
      }
    });

    test('finds every shot of a fast string whose bursts run into each other',
        () {
      const times = [1.0, 1.27, 1.52, 1.8, 2.05, 2.33];
      final clip = syntheticClip(
        seconds: 4,
        shots: times,
        shot: (x, at, rand) => addHeldBurst(x, at, rand, holdSeconds: 0.15),
      );
      final shots = shotsIn(clip);
      expect(shots, hasLength(times.length));
      for (var i = 0; i < times.length; i++) {
        expect(shots[i].frame / 374.67, closeTo(times[i], 0.01));
      }
    });

    test('does not count the echo off the berm as a shot', () {
      final clip = syntheticClip(
        shot: (x, at, rand) {
          addShot(x, at, rand);
          addShot(x, at + 0.19, rand, gain: 0.15);
        },
      );
      expect(shotsIn(clip), hasLength(5));
    });

    test('does not count footsteps between shots', () {
      final clip = syntheticClip(
        seconds: 8,
        extra: (x) {
          final rand = referenceNoise();
          for (final at in [5.2, 5.6, 6.0, 6.4]) {
            addShot(x, at, rand, gain: 0.03, blastSeconds: 0.006);
          }
        },
      );
      expect(shotsIn(clip), hasLength(5));
    });
  });

  test('a higher gate keeps the clear shots and moves the gate', () {
    final spectrogram = Spectrogram.compute(
      syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
      clipSampleRate,
    );
    final normal = findShots(spectrogram);
    final strict = findShots(spectrogram, gateScale: 1.05);
    expect(strict.gate, greaterThan(normal.gate));
    expect(normal.shots, hasLength(5));
    expect(strict.shots, hasLength(5));
  });
}
