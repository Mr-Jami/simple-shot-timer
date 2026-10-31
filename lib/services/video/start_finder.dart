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
/// * if several strings qualify, the one with the most shots in the
///   [windowSeconds] after its tone wins, the earlier one on a tie.
///
/// Returns null when no tone qualifies. There is no fallback to 0 s.
///
/// Timing alone can't tell a beep from steel ringing that reaches the
/// camera more than [quietBefore] after its hit (long-range steel), or from
/// another bay's beep and shot just before yours: tone, shot, tone, shots
/// either way. Then the count decides, and the editor's Set START fixes it.
ToneRun? chooseStart(
  List<ToneRun> tones,
  List<double> shotSeconds, {
  List<double>? hitSeconds,
  double minDraw = minDrawSeconds,
  double maxDraw = 10,
  double quietBefore = 1.0,
  double attackSeconds = 0.03,
  double windowSeconds = 10,
}) {
  final hits = hitSeconds ?? shotSeconds;
  final candidates = [
    for (final t in tones)
      if (!hits.any((s) =>
          s < t.onsetSeconds - attackSeconds &&
          s >= t.onsetSeconds - quietBefore))
        t,
  ];
  ToneRun? best;
  var bestCount = 0;
  for (final tone in candidates) {
    final t0 = tone.onsetSeconds;
    final after =
        shotSeconds.where((s) => s > t0 + minDraw && !isStopClick(tone, s));
    if (after.isEmpty) continue;
    final firstShot = after.first;
    if (firstShot - t0 > maxDraw) continue;
    final laterTone = candidates
        .any((c) => c.onsetSeconds > t0 && c.onsetSeconds < firstShot);
    if (laterTone) continue;
    final count = after.where((s) => s <= t0 + windowSeconds).length;
    if (count > bestCount) {
      best = tone;
      bestCount = count;
    }
  }
  return best;
}
