// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrogram.dart';

/// A shot found in a clip, at the spectrogram frame where its onset is.
class ShotHit {
  const ShotHit(this.frame);

  final int frame;

  @override
  bool operator ==(Object other) => other is ShotHit && other.frame == frame;

  @override
  int get hashCode => frame.hashCode;

  @override
  String toString() => 'ShotHit($frame)';
}

/// Every shot [findShots] accepted, and the loudness gate it used.
class ShotScan {
  const ShotScan({required this.shots, required this.gate});

  final List<ShotHit> shots;

  /// Mean bin value a frame had to exceed to count. Diagnostics only.
  final double gate;
}

/// Finds shots in a whole clip with the transient test of the video shot
/// timer reference (`shot-detector.mjs`). On the reference's own synthetic
/// clip it returns the same frames.
///
/// Per frame m, for each of the 128 bins: +1 when the level rises sharply at
/// m, falls again within two frames and decays over the next 100 ms; −1 when
/// it is already decaying. A shot is a frame where the net score is above
/// 20 % of the bins, the frame's mean level is above the adaptive loudness
/// gate, and the previous shot is more than 100 ms back.
///
/// The reference re-averages its windows for every frame. Here the "early"
/// and "late" windows are sliding per-bin sums, so the work per frame no
/// longer grows with the window length.
///
/// [gateScale] multiplies the loudness gate (see `ShotSensitivity`).
ShotScan findShots(Spectrogram s, {double gateScale = 1.0}) {
  const bins = Spectrogram.bins;
  final v = s.values;
  final frameCount = s.frameCount;
  final fps = s.framesPerSecond;
  final lookahead = (0.28 * fps).round();
  final lookback = (0.05 * fps).round();
  final minSplit = (0.1 * fps).round();

  // Row sums, and the adaptive gate from the per-frame mean level: 95 % of
  // the average of the loudest frame and the midpoint between the mean frame
  // and the loudest one. Summed in frame order, like the reference.
  final rowSum = Int32List(frameCount);
  var meanSum = 0.0;
  var meanCount = 0;
  var maxMean = 0.0;
  for (var m = 0; m < frameCount; m++) {
    var sum = 0;
    final row = m * bins;
    for (var k = 0; k < bins; k++) {
      sum += v[row + k];
    }
    rowSum[m] = sum;
    if (m < 2) continue;
    final mean = sum / bins;
    meanSum += mean;
    meanCount++;
    if (mean > maxMean) maxMean = mean;
  }
  if (meanCount == 0) return const ShotScan(shots: [], gate: 0);
  final average = meanSum / meanCount;
  final gate = (((average + maxMean) * 0.5 + maxMean) / 2) * 0.95 * gateScale;

  // The "early" part of the refractory window (0-50 ms ahead) must be louder
  // than the "late" part (50-100 ms ahead): the sound decays like a shot. The
  // window holds frames m+1 .. m+minSplit, split at minSplit / 2 exactly as
  // the reference splits it.
  final earlyLen = (minSplit / 2).ceil();
  final lateFirst = (minSplit / 2).floor() + 1;
  final lateLen = minSplit - lateFirst;

  // The reference skips frames without lookback history or a full lookahead.
  final first = math.max(1, lookback + 1);
  final last = frameCount - lookahead;
  final shots = <ShotHit>[];
  if (last < first || lateLen <= 0) return ShotScan(shots: shots, gate: gate);

  final early = Int32List(bins);
  final late = Int32List(bins);
  void slide(Int32List sums, int frame, int sign) {
    final row = frame * bins;
    for (var k = 0; k < bins; k++) {
      sums[k] += sign * v[row + k];
    }
  }

  for (var g = 0; g < earlyLen; g++) {
    slide(early, first + 1 + g, 1);
  }
  for (var g = lateFirst; g < minSplit; g++) {
    slide(late, first + 1 + g, 1);
  }

  var lastShot = 0;
  for (var m = first; m <= last; m++) {
    if (m > first) {
      slide(early, m, -1);
      slide(early, m + earlyLen, 1);
      slide(late, m + lateFirst, -1);
      slide(late, m + minSplit, 1);
    }
    if (rowSum[m] / bins <= gate || m - lastShot <= minSplit) continue;

    final r0 = m * bins;
    var score = 0;
    for (var k = 0; k < bins; k++) {
      final now = v[r0 + k] + v[r0 + bins + k];
      final prev = v[r0 - bins + k] + v[r0 - 2 * bins + k];
      final prev2 = v[r0 - 3 * bins + k] + v[r0 - 4 * bins + k];
      final next = v[r0 + 2 * bins + k] + v[r0 + 3 * bins + k];
      final next2 = v[r0 + 4 * bins + k] + v[r0 + 5 * bins + k];
      if (now > prev &&
          now > next &&
          next > prev &&
          early[k] / earlyLen > late[k] / lateLen) {
        score++;
      }
      if (next2 < prev2 && next < prev) score--;
    }
    if (score / bins > 0.2) {
      shots.add(ShotHit(m));
      lastShot = m;
    }
  }
  return ShotScan(shots: shots, gate: gate);
}
