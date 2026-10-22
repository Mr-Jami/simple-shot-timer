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
