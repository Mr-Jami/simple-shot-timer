// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrogram.dart';

/// A shot found in a clip, at the spectrogram frame where its onset is.
class ShotHit {
  const ShotHit(this.frame, {this.soft = false});

  final int frame;

  /// Found by the softer onset test rather than the reference test.
  final bool soft;

  @override
  bool operator ==(Object other) =>
      other is ShotHit && other.frame == frame && other.soft == soft;

  @override
  int get hashCode => Object.hash(frame, soft);

  @override
  String toString() => 'ShotHit($frame${soft ? ', soft' : ''})';
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
/// The reference test wants a crack that peaks within two frames. Re-encoded
/// clips and phone cameras with automatic gain control smear that over tens
/// of milliseconds, so the test misses those shots, often the first one.
/// [softOnsets] adds them with [_softShots].
///
/// [gateScale] multiplies the loudness gate (see `ShotSensitivity`).
ShotScan findShots(
  Spectrogram s, {
  double gateScale = 1.0,
  bool softOnsets = true,
}) {
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
  if (softOnsets) {
    shots
      ..addAll(_softShots(s, rowSum, gate, shots, minSplit: minSplit))
      ..sort((a, b) => a.frame.compareTo(b.frame));
  }
  return ShotScan(shots: shots, gate: gate);
}

// Thresholds of _softShots, on the spectrogram's byte scale.
const double _minRise = 40;
const double _minRisingBins = 0.65;
const double _gateMargin = 12;
const double _loudMinRise = 15;
const double _loudMinRisingBins = 0.45;
const double _echoSeconds = 0.3;
const double _echoMargin = 15;

/// Shots the reference test misses because their onset is smeared: a broad
/// rise of the whole spectrum that reaches nearly the loudness gate.
///
/// A frame qualifies where the frame mean rises by at least [_minRise] units
/// (about 18 dB) across four frames, at least [_minRisingBins] of the bins
/// rise by 10 units (4.4 dB), and the loudest of the next five frames comes
/// within [_gateMargin] units (about 5 dB) of [gate]. Footsteps and movement
/// are steep enough but tens of units too quiet.
///
/// It only adds shots more than [minSplit] frames (100 ms) from every
/// [strict] one, so a clip the reference test handles keeps exactly its
/// frames. Within [_echoSeconds] after a shot, a rise must also come within
/// [_echoMargin] units of that shot's level: an echo off the berm or a wall
/// arrives about 0.2 s later and at least 18 units quieter, while real fast
/// splits stay within about 11.
///
/// The thresholds are set on hand-checked range clips whose timers showed
/// every shot (see the video feature's issue draft).
List<ShotHit> _softShots(
  Spectrogram s,
  Int32List rowSum,
  double gate,
  List<ShotHit> strict, {
  required int minSplit,
}) {
  const bins = Spectrogram.bins;
  final v = s.values;
  final fps = s.framesPerSecond;
  double mean(int m) => rowSum[m] / bins;
  double rise(int m) => mean(m + 2) - mean(m - 2);
  double peak(int m) {
    var best = mean(m);
    for (var j = m + 1; j <= m + 4 && j < s.frameCount; j++) {
      if (mean(j) > best) best = mean(j);
    }
    return best;
  }

  final echoFrames = (_echoSeconds * fps).round();
  final accepted = <int>[for (final h in strict) h.frame];
  final soft = <ShotHit>[];
  for (var m = 3; m < s.frameCount - 5; m++) {
    final r = rise(m);
    // The middle of the steepest rise, where the onset is.
    if (r < _loudMinRise || r < rise(m - 1) || r <= rise(m + 1)) continue;
    final level = peak(m);
    if (level < gate - _gateMargin) continue;
    if (accepted.any((a) => (a - m).abs() <= minSplit)) continue;
    var risingBins = 0;
    for (var k = 0; k < bins; k++) {
      if (v[(m + 2) * bins + k] - v[(m - 2) * bins + k] >= 10) risingBins++;
    }
    final rising = risingBins / bins;
    final steep = r >= _minRise && rising >= _minRisingBins;
    // A shot that lands while the previous one still rings rises less, but
    // is as loud as the gate.
    final loud = level >= gate && rising >= _loudMinRisingBins;
    if (!steep && !loud) continue;
    int? previous;
    for (final a in accepted) {
      if (a < m && (previous == null || a > previous)) previous = a;
    }
    if (previous != null &&
        m - previous <= echoFrames &&
        level < peak(previous) - _echoMargin) {
      continue;
    }
    soft.add(ShotHit(m, soft: true));
    accepted.add(m);
  }
  return soft;
}
