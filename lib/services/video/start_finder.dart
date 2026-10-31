// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'tone_finder.dart';

/// The shortest possible draw: nobody reacts to a beep faster, so a "shot"
/// sooner after it is the beep's own attack.
const double minDrawSeconds = 0.1;

/// Whether a "shot" at [seconds] is the click of [tone] stopping. A piezo
/// beep that stops abruptly clicks, measured from just before the tone's end
/// to a little after it.
bool isStopClick(ToneRun tone, double seconds) =>
    seconds >= tone.endSeconds - 0.01 && seconds <= tone.endSeconds + 0.05;

/// Picks the start beep among [tones], given the string's shot times in
/// [shotSeconds] and every hit the shot test found in [hitSeconds] (the
/// shots plus what the shot filter dropped; by default the shots), both
/// ascending. START is the last real tone before a string of shots:
///
/// * a tone that starts within [quietBefore] after a hit is steel ringing
///   after a hit or an end beep, never START. A hit in the last
///   [attackSeconds] before the onset doesn't count: that is the click of a
///   piezo beep switching on, measured a hair early;
/// * a shot must follow the tone within [maxDraw], and no sooner than
///   [minDraw]. A slow start (getting into position for long-range steel)
///   can take over 8 s; past [windowSeconds] no shot would count anyway.
///   The tone's own stop click is not a shot, and neither is a dropped hit:
///   a button click between a chirp and the beep doesn't make the chirp
///   START;
/// * of several tones before the same first shot, the last one wins: button
///   chirps and range commands come before the real beep;
/// * a tone within another tone's string (past its first shot and inside
///   its window) that starts within [ringGap] after a hit is steel ringing
///   that reached the camera late, as from long-range steel, never START.
///   A beep for a second string comes after a longer pause;
/// * if several strings qualify, the one with the most shots in the
///   [windowSeconds] after its tone wins, the earlier one on a tie.
///
/// Returns null when no tone qualifies. There is no fallback to 0 s.
ToneRun? chooseStart(
  List<ToneRun> tones,
  List<double> shotSeconds, {
  List<double>? hitSeconds,
  double minDraw = minDrawSeconds,
  double maxDraw = 10,
  double quietBefore = 1.0,
  double ringGap = 3.0,
  double attackSeconds = 0.03,
  double windowSeconds = 10,
}) {
  final hits = hitSeconds ?? shotSeconds;
  bool hitBefore(ToneRun t, double within) => hits.any((s) =>
      s < t.onsetSeconds - attackSeconds && s >= t.onsetSeconds - within);
  final candidates = [
    for (final t in tones)
      if (!hitBefore(t, quietBefore)) t,
  ];

  /// The tone's string: its shots, or null when none follows within
  /// [maxDraw].
  List<double>? stringOf(ToneRun tone) {
    final t0 = tone.onsetSeconds;
    final after = [
      for (final s in shotSeconds)
        if (s > t0 + minDraw && !isStopClick(tone, s)) s,
    ];
    return after.isEmpty || after.first - t0 > maxDraw ? null : after;
  }

  final strings = {for (final t in candidates) t: stringOf(t)};
  bool duringString(ToneRun tone) => strings.entries.any((e) {
        final t0 = e.key.onsetSeconds;
        final shots = e.value;
        return shots != null &&
            shots.first < tone.onsetSeconds &&
            tone.onsetSeconds <= t0 + windowSeconds;
      });

  ToneRun? best;
  var bestCount = 0;
  for (final tone in candidates) {
    final t0 = tone.onsetSeconds;
    final after = strings[tone];
    if (after == null) continue;
    final firstShot = after.first;
    final laterTone = candidates.any(
        (c) => c.onsetSeconds > t0 && c.onsetSeconds < firstShot);
    if (laterTone) continue;
    if (hitBefore(tone, ringGap) && duringString(tone)) continue;
    final count = after.where((s) => s <= t0 + windowSeconds).length;
    if (count > bestCount) {
      best = tone;
      bestCount = count;
    }
  }
  return best;
}
