// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_signal.dart';
import 'package:simple_shot_timer/utils/timeline_math.dart';

import 'clip_fixtures.dart';

void main() {
  group('zooming', () {
    test('keeps the moment under the fingers', () {
      const focalPx = 120.0;
      final before = 5000 + focalPx / 100 * 1000;
      final playhead = zoomAround(
        playheadMs: 5000,
        focalPx: focalPx,
        oldPxPerSecond: 100,
        newPxPerSecond: 400,
      );
      expect(playhead + focalPx / 400 * 1000, closeTo(before, 1e-9));
    });

    test('stays between whole strings and single milliseconds', () {
      expect(clampZoom(10), minPxPerSecond);
      expect(clampZoom(1e6), maxPxPerSecond);
      expect(clampZoom(300), 300);
    });
  });

  test('the rubber band gives less the further it is pulled', () {
    final small = rubberBand(20, 400);
    final big = rubberBand(200, 400);
    expect(small, lessThan(20));
    expect(big, lessThan(200));
    expect(big / 200, lessThan(small / 20));
    expect(rubberBand(-50, 400), -rubberBand(50, 400));
  });

  test('a marker counts as crossed when the playhead passes or reaches it', () {
    expect(crossesMarker(990, 1010, [1000]), isTrue);
    expect(crossesMarker(1010, 990, [1000]), isTrue);
    expect(crossesMarker(990, 1000, [1000]), isTrue);
    expect(crossesMarker(1000, 1010, [1000]), isFalse);
    expect(crossesMarker(990, 999, [1000]), isFalse);
  });

  group('the clip signal', () {
    final clip = AnalyzedClip(
      info: const ClipInfo(hasAudio: true, durationMs: 7000),
      analysis: analyzePcm(syntheticClip(), clipSampleRate),
      audioOriginMs: 0,
    );

    test('snaps a shot dropped a few ms off back onto its onset', () {
      final detected = clip.toClipMs(clip.analysis.shotSeconds[1]);
      for (final off in [-7, -3, 4, 7]) {
        expect(clip.snapToOnset(detected + off), closeTo(detected, 3),
            reason: 'dropped $off ms off');
      }
    });

    test('finds nothing to snap to in quiet', () {
      expect(clip.snapToOnset(1500), isNull);
    });

    test('loudness: amplitude against the loud end, clipped frames aside',
        () {
      // 45 units are a factor of ten; the 40th loudest frame is the top,
      // so a few clipped frames don't make the rest look quiet.
      final levels = Float32List(1000)..fillRange(0, 1000, 150);
      levels[3] = 105;
      levels.fillRange(10, 49, 255);
      final out = loudness(levels);
      expect(out[0], 1);
      expect(out[3], closeTo(0.1, 1e-6));
      expect(out[10], 1);
      expect(loudness(Float32List(0)), isEmpty);
    });

    test('loudness: a long clip draws as tall as a short one', () {
      // The same 0.4 s string (150 frames at 150, its loud end at 200) in
      // 10 s and in 3 minutes of quiet.
      Float32List clip(int frames) {
        final levels = Float32List(frames)..fillRange(0, frames, 60);
        levels.fillRange(100, 250, 150);
        levels.fillRange(100, 140, 200);
        return levels;
      }

      expect(loudness(clip(3750))[200],
          closeTo(loudness(clip(67500))[200], 1e-6));
      expect(loudness(clip(67500))[200], closeTo(0.077, 0.001));
    });

    test('column peaks keep a one-frame shot at every zoom', () {
      final values = Float32List(1000)..[617] = 1;
      // Zoomed out: 7.5 frames a column, the shot in column 82.
      final wide = columnPeaks(values, first: 0, perColumn: 7.5, columns: 133);
      expect(wide[82], 1);
      expect(wide.where((v) => v > 0), hasLength(1));
      // Zoomed in: 5 columns a frame, all five show it.
      final narrow =
          columnPeaks(values, first: 616, perColumn: 0.2, columns: 15);
      expect([for (final v in narrow) v], [
        for (var c = 0; c < 15; c++) c >= 5 && c < 10 ? 1.0 : 0.0,
      ]);
      // Before the first frame and past the last: nothing.
      expect(columnPeaks(values, first: -20, perColumn: 1, columns: 10),
          everyElement(0));
      expect(columnPeaks(values, first: 995, perColumn: 1, columns: 10)[8], 0);
    });

    test('keeps a short loud frame in the minimap', () {
      final levels = Float32List(1000)..[617] = 200;
      final buckets = bucketMax(levels, 50);
      expect(buckets, hasLength(50));
      expect(buckets.reduce((a, b) => a > b ? a : b), 200);
      expect(frameLevels(clip.analysis.spectrogram),
          hasLength(clip.analysis.spectrogram.frameCount));
    });
  });
}
