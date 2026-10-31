// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;

import 'clip_shot_finder.dart';
import 'spectrogram.dart';

// Thresholds of keepShotLike, on the spectrogram's byte scale.
const int _minHits = 3;
const double _isolationFactor = 1.4;
const double _minIsolationLimit = 6.5;
const double _minBoom = 15;
const double _echoSeconds = 0.3;
const double _echoMargin = 6;

/// The hits that sound like shots of this string: [hits] without the gun
/// handling a camera on or next to the shooter records as loud as the
/// shots (loading, a reload, the magazine landing on concrete, unloading,
/// holstering, brass).
///
/// One gun filmed by one camera sounds the same shot after shot; handling
/// noises each sound different. A hit's isolation is how far its sound
/// (spectrum at the peak and its decay, see [_sound]) is from the hit that
/// sounds second most like it. The clip's scale is the median isolation
/// of its most alike quarter of hits, at least three: its shots. A hit
/// whose isolation is above [_isolationFactor] times that scale, and above
/// [_minIsolationLimit] (a clip of near-identical shots would otherwise
/// drop a shot fired from another spot), goes, unless it has a gunshot's
/// boom: its low band at least [_minBoom] units (about 7 dB) above 4-12
/// kHz. Clicks and metal on metal have no boom; a shot that sounds unlike
/// the others (another position, turned away) mostly keeps it. So does the
/// echo of a shot, which therefore also goes when it comes within
/// [_echoSeconds] of a hit at least [_echoMargin] units (about 3 dB)
/// louder.
///
/// With fewer than [_minHits] hits there is nothing to compare: all stay.
/// A thump with a strong low end away from the shots (a magazine slapped
/// home) can stay too.
///
/// The thresholds are set on the user's range clips, where the shots are
/// known from the timer shown at the end or from the video, and checked on
/// the competition clips; `test/shot_filter_test.dart` pins them on
/// synthetic clips.
List<ShotHit> keepShotLike(Spectrogram s, List<ShotHit> hits) {
  if (hits.length < _minHits) return hits;
  final sounds = [for (final h in hits) _sound(s, h.frame)];
  final isolation = [
    for (var i = 0; i < hits.length; i++)
      ([
        for (var j = 0; j < hits.length; j++)
          if (j != i) _distance(sounds[i], sounds[j])
      ]..sort())[1],
  ];
  final sorted = [...isolation]..sort();
  final alike = sorted.take(math.max(3, hits.length ~/ 4)).toList();
  final limit = math.max(
    _isolationFactor * alike[alike.length ~/ 2],
    _minIsolationLimit,
  );
  final shotLike = [for (final x in isolation) x <= limit];
  final level = [
    for (final h in hits) _band(s, _peak(s, h.frame), 0, Spectrogram.bins),
  ];
  // An echo off the far wall comes 0.15-0.2 s after a shot, keeps its boom
  // and is quieter; a fast follow-up shot that sounds a little different is
  // about as loud as the one before.
  final echoFrames = (_echoSeconds * s.framesPerSecond).round();
  bool echo(int i) {
    for (var j = i - 1;
        j >= 0 && hits[i].frame - hits[j].frame <= echoFrames;
        j--) {
      if (level[i] <= level[j] - _echoMargin) return true;
    }
    return false;
  }

  return [
    for (final (i, h) in hits.indexed)
      if (shotLike[i] ||
          (_boom(s, _peak(s, h.frame)) >= _minBoom && !echo(i)))
        h,
  ];
}

/// Mean value of bins [from, to) in [frame]; 0 past the end.
double _band(Spectrogram s, int frame, int from, int to) {
  if (frame < 0 || frame >= s.frameCount) return 0;
  final row = frame * Spectrogram.bins;
  var sum = 0;
  for (var k = from; k < to; k++) {
    sum += s.values[row + k];
  }
  return sum / (to - from);
}

/// The loudest frame within 20 ms of the onset [frame].
int _peak(Spectrogram s, int frame) {
  final span = (0.02 * s.framesPerSecond).round();
  var peak = frame;
  for (var m = frame + 1; m < frame + span; m++) {
    if (_band(s, m, 0, Spectrogram.bins) >
        _band(s, peak, 0, Spectrogram.bins)) {
      peak = m;
    }
  }
  return peak;
}

/// A hit's sound: 16 bands from one bin up to 64 bins (about 0.2-12 kHz at
/// 48 kHz) over four frames from the peak, less their mean so the level
/// doesn't count; then the frame mean 10, 20, 40, 80 and 150 ms after the
/// peak, against the peak's. A point past the end of the clip (or part) is
/// NaN, not silence: a last shot cut off there would look unlike the others.
List<double> _sound(Spectrogram s, int onset) {
  final p = _peak(s, onset);
  final frames = math.min(4, s.frameCount - p);
  final shape = [
    for (var b = 0; b < 16; b++)
      [for (var m = p; m < p + frames; m++) _band(s, m, 1 + 4 * b, 5 + 4 * b)]
              .reduce((x, y) => x + y) /
          frames,
  ];
  final mean = shape.reduce((x, y) => x + y) / shape.length;
  final level = _band(s, p, 0, Spectrogram.bins);
  return [
    for (final v in shape) v - mean,
    for (final ms in const [10, 20, 40, 80, 150])
      if (p + (ms / 1000 * s.framesPerSecond).round() case final m
          when m < s.frameCount)
        _band(s, m, 0, Spectrogram.bins) - level
      else
        double.nan,
  ];
}

/// Root mean square difference of two sounds, over the points both have.
double _distance(List<double> a, List<double> b) {
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i].isNaN || b[i].isNaN) continue;
    sum += (a[i] - b[i]) * (a[i] - b[i]);
    n++;
  }
  return math.sqrt(sum / n);
}

/// How much the low band (bins 1-5, about 0.2-1.1 kHz) stands above 4-12
/// kHz (bins 22-63) in the [peak] frame.
double _boom(Spectrogram s, int peak) =>
    _band(s, peak, 1, 6) - _band(s, peak, 22, 64);
