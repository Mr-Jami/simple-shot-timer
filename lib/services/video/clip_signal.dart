// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'spectrogram.dart';

// What the editor reads from a clip's spectrogram besides the analyzer's
// verdict: a loudness envelope for the minimap and onsets to snap a moved
// shot to. Times are frames here; AnalyzedClip turns them into clip time.

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
