// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrogram.dart';

// What the editor reads from a clip's spectrogram besides the analyzer's
// verdict: the loudness its timeline and minimap draw and onsets to snap a
// moved shot to. Times are frames here; AnalyzedClip turns them into clip
// time.

/// Mean level of every frame, on the spectrogram's byte scale.
Float32List frameLevels(Spectrogram s) {
  const bins = Spectrogram.bins;
  final v = s.values;
  final levels = Float32List(s.frameCount);
  for (var m = 0; m < s.frameCount; m++) {
    var sum = 0;
    final row = m * bins;
    for (var k = 0; k < bins; k++) {
      sum += v[row + k];
    }
    levels[m] = sum / bins;
  }
  return levels;
}

/// [levels] as loudness from 0 to 1, the way a voice recorder draws sound:
/// the amplitude against the clip's loud end, its 40th loudest frame (about
/// a tenth of a second), so a few clipped frames don't flatten the rest and
/// a long clip draws as tall as a short one. 45 units of the byte scale are
/// a factor of ten, so shots stand tall and room noise stays near 0.
Float32List loudness(Float32List levels) {
  final out = Float32List(levels.length);
  if (levels.isEmpty) return out;
  final sorted = Float32List.fromList(levels)..sort();
  final loud = sorted[math.max(0, sorted.length - 40)];
  for (var m = 0; m < levels.length; m++) {
    out[m] = math.min(1, math.pow(10, (levels[m] - loud) / 45).toDouble());
  }
  return out;
}

/// The loudest of [values] in each of [columns] columns, the first starting
/// at frame [first] and each [perColumn] frames wide (both may be
/// fractions): a column takes every frame it touches, so a one-frame shot
/// shows at any zoom. 0 where there are no frames.
Float32List columnPeaks(
  Float32List values, {
  required double first,
  required double perColumn,
  required int columns,
}) {
  final out = Float32List(math.max(0, columns));
  for (var c = 0; c < out.length; c++) {
    final from = (first + c * perColumn).floor();
    final to = math.max(from + 1, (first + (c + 1) * perColumn).ceil());
    var best = 0.0;
    for (var m = math.max(0, from); m < math.min(to, values.length); m++) {
      if (values[m] > best) best = values[m];
    }
    out[c] = best;
  }
  return out;
}

/// [levels] squeezed into [buckets] by keeping each bucket's loudest frame,
/// so a short shot stays visible however far the minimap is zoomed out.
Float32List bucketMax(Float32List levels, int buckets) {
  final out = Float32List(buckets);
  if (levels.isEmpty || buckets <= 0) return out;
  for (var b = 0; b < buckets; b++) {
    final from = b * levels.length ~/ buckets;
    final to =
        ((b + 1) * levels.length ~/ buckets).clamp(from + 1, levels.length);
    var best = levels[from];
    for (var m = from + 1; m < to; m++) {
      if (levels[m] > best) best = levels[m];
    }
    out[b] = best;
  }
  return out;
}

/// How sharply the whole spectrum rises into frame [m]: the summed positive
/// change of every bin from the frame before. Shots spike it; a steady beep
/// or ringing hardly moves it.
int onsetStrength(Spectrogram s, int m) {
  if (m <= 0 || m >= s.frameCount) return 0;
  const bins = Spectrogram.bins;
  final v = s.values;
  final row = m * bins;
  final prev = row - bins;
  var flux = 0;
  for (var k = 0; k < bins; k++) {
    final rise = v[row + k] - v[prev + k];
    if (rise > 0) flux += rise;
  }
  return flux;
}

/// The frame within [radiusFrames] of [frame] where a sound starts most
/// sharply, or null when nothing there rises like a shot: at least
/// [minRisePerBin] byte units (about 5 dB) on average across the spectrum,
/// and three times the typical rise around it (the median over a quarter
/// second either side), so noise and a steady background never snap.
int? strongestOnset(
  Spectrogram s,
  int frame, {
  required int radiusFrames,
  double minRisePerBin = 12,
}) {
  final around = (s.framesPerSecond / 4).round();
  final nearby = [
    for (var m = frame - around; m <= frame + around; m++) onsetStrength(s, m),
  ]..sort();
  final typical = nearby.isEmpty ? 0 : nearby[nearby.length ~/ 2];
  int? best;
  var bestStrength = [(minRisePerBin * Spectrogram.bins).round(), 3 * typical]
      .reduce((a, b) => a > b ? a : b);
  for (var m = frame - radiusFrames; m <= frame + radiusFrames; m++) {
    final strength = onsetStrength(s, m);
    if (strength > bestStrength) {
      best = m;
      bestStrength = strength;
    }
  }
  return best;
}
