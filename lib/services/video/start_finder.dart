// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'tone_finder.dart';

/// Picks the start beep among [tones], given the shot times in [shotSeconds]
/// (ascending). START is the last real tone before a string of shots:
///
/// * a tone that starts within [quietBefore] after a shot is steel ringing
///   after a hit or an end beep, never START;
/// * a shot must follow the tone within [maxDraw], and no sooner than
///   [minDraw] (nobody reacts that fast, so an earlier "shot" is the beep's
///   own attack);
/// * of several tones before the same first shot, the last one wins: button
///   chirps and range commands come before the real beep;
/// * if several strings qualify, the one with the most shots in the
///   [windowSeconds] after its tone wins, the earlier one on a tie.
///
/// Returns null when no tone qualifies. There is no fallback to 0 s.
ToneRun? chooseStart(
  List<ToneRun> tones,
  List<double> shotSeconds, {
  double minDraw = 0.1,
  double maxDraw = 8,
  double quietBefore = 1.0,
  double windowSeconds = 10,
}) {
  final candidates = [
    for (final t in tones)
      if (!shotSeconds.any(
          (s) => s <= t.onsetSeconds && s >= t.onsetSeconds - quietBefore))
        t,
  ];
  ToneRun? best;
  var bestCount = 0;
  for (final tone in candidates) {
    final t0 = tone.onsetSeconds;
    final after = shotSeconds.where((s) => s > t0 + minDraw);
    if (after.isEmpty) continue;
    final firstShot = after.first;
    if (firstShot - t0 > maxDraw) continue;
    final laterTone = candidates.any(
        (c) => c.onsetSeconds > t0 && c.onsetSeconds < firstShot);
    if (laterTone) continue;
    final count = after.where((s) => s <= t0 + windowSeconds).length;
    if (count > bestCount) {
      best = tone;
      bestCount = count;
    }
  }
  return best;
}
