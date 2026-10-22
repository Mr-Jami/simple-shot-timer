// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrogram.dart';

/// A steady tone in a clip: a start beep, a par beep, a whistle, steel
/// ringing, a button chirp. `chooseStart` decides which one, if any, is START.
class ToneRun {
  const ToneRun({
    required this.startFrame,
    required this.endFrame,
    required this.frequencyHz,
    required this.onsetSeconds,
    required this.framesPerSecond,
  });

  /// First tonal frame.
  final int startFrame;

  /// Last tonal frame (inclusive).
  final int endFrame;

  /// Median peak frequency, to the spectrogram's bin width (~190 Hz).
  final double frequencyHz;

  /// Where the tone becomes audible, refined on the waveform to about a
  /// millisecond (see [refineToneOnset]). START uses this.
  final double onsetSeconds;
  final double framesPerSecond;

  double get startSeconds => startFrame / framesPerSecond;
  double get endSeconds => (endFrame + 1) / framesPerSecond;
  double get durationSeconds => endSeconds - startSeconds;

  ToneRun withOnset(double seconds) => ToneRun(
        startFrame: startFrame,
        endFrame: endFrame,
        frequencyHz: frequencyHz,
        onsetSeconds: seconds,
        framesPerSecond: framesPerSecond,
      );

  @override
  String toString() => 'ToneRun(${onsetSeconds.toStringAsFixed(3)}s, '
      '${(durationSeconds * 1000).round()} ms, ${frequencyHz.round()} Hz)';
}

/// Steady tones between [minHz] and [maxHz] with at least [minSeconds] of
/// tonal frames, which a 0.1 s beep has and a short chirp or the ping of a
/// steel hit does not.
///
/// A frame is tonal when its loudest bin in that band stands at least
/// [minProminence] units (about 10 dB) above the band's median, which a
/// broadband shot does not, and at least [minSharpness] units (about 9 dB)
/// above the bins three to either side, which rumble, wind and voices do not:
/// their energy is spread, a beep's sits in one narrow line.
///
/// Tonal frames whose peak stays within one bin form a run; up to
/// [maxGapFrames] dropouts are bridged, for example where a shot lands on a
/// beep. Runs of the same pitch less than [mergeSeconds] apart are one tone,
/// so a double beep ("beep-beep") counts once, from its first pulse.
List<ToneRun> findTones(
  Spectrogram s, {
  double minHz = 1000,
  double maxHz = 6000,
  double minSeconds = 0.08,
  int minProminence = 24,
  int minSharpness = 20,
  int maxGapFrames = 3,
  double mergeSeconds = 0.3,
}) {
  const bins = Spectrogram.bins;
  final fps = s.framesPerSecond;
  final lo = (minHz / s.binHz).ceil().clamp(3, bins - 4);
  final hi = (maxHz / s.binHz).floor().clamp(lo, bins - 4);
  final width = hi - lo + 1;
  final band = Int32List(width);
  final v = s.values;

  // Raw runs: start, end, and every frame's peak bin.
  final raw = <({int start, int end, List<int> peaks})>[];
  var start = -1, end = -1, runPeak = -1;
  var peaks = <int>[];
  void close() {
    if (start >= 0) raw.add((start: start, end: end, peaks: peaks));
    start = end = runPeak = -1;
    peaks = <int>[];
  }

  for (var m = 0; m < s.frameCount; m++) {
    final row = m * bins;
    var peak = lo;
    for (var k = lo; k <= hi; k++) {
      band[k - lo] = v[row + k];
      if (v[row + k] > v[row + peak]) peak = k;
    }
    band.sort();
    final median = band[width ~/ 2];
    final level = v[row + peak];
    final shoulder = math.max(v[row + peak - 3], v[row + peak + 3]);
    final tonal =
        level - median >= minProminence && level - shoulder >= minSharpness;

    if (tonal &&
        start >= 0 &&
        (peak - runPeak).abs() <= 1 &&
        m - end <= maxGapFrames + 1) {
      end = m;
      runPeak = peak;
      peaks.add(peak);
    } else if (tonal) {
      close();
      start = end = m;
      runPeak = peak;
      peaks.add(peak);
    } else if (start >= 0 && m - end > maxGapFrames) {
      close();
    }
  }
  close();

  // Merge same-pitch runs that are close together, then keep the long ones.
  final mergeFrames = (mergeSeconds * fps).round();
  final merged = <({int start, int end, List<int> peaks})>[];
  for (final r in raw) {
    if (merged.isNotEmpty) {
      final prev = merged.last;
      final samePitch = (_median(prev.peaks) - _median(r.peaks)).abs() <= 1;
      if (samePitch && r.start - prev.end <= mergeFrames) {
        merged[merged.length - 1] =
            (start: prev.start, end: r.end, peaks: [...prev.peaks, ...r.peaks]);
        continue;
      }
    }
    merged.add(r);
  }
  final minFrames = (minSeconds * fps).ceil();
  return [
    for (final r in merged)
      if (r.peaks.length >= minFrames)
        ToneRun(
          startFrame: r.start,
          endFrame: r.end,
          frequencyHz: _median(r.peaks) * s.binHz,
          onsetSeconds: r.start / fps,
          framesPerSecond: fps,
        ),
  ];
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Refines where a tone becomes audible, to about a millisecond.
///
/// Runs a Goertzel filter at [frequencyHz] over 128-sample blocks every 16
/// samples around [coarseSeconds]. It measures the tone's steady level from
/// 30 to 90 ms in and the noise at that pitch just before, then returns the
/// centre of the first block that reaches a fifth of the tone's amplitude
/// (−14 dB), stays there for four steps, and stands 6 dB clear of the noise.
/// The spectrogram's own onset is only good to a few frames, because a tone
/// has to stand 10 dB clear of the band there.
///
/// Returns [coarseSeconds] when the rise can't be told from the noise.
double refineToneOnset(
  Int16List pcm,
  int sampleRate,
  double frequencyHz,
  double coarseSeconds,
) {
  const block = 128;
  const step = 16;
  const hold = 4;
  final coeff = 2 * math.cos(2 * math.pi * frequencyHz / sampleRate);
  double power(int start) {
    var s1 = 0.0, s2 = 0.0;
    for (var i = 0; i < block; i++) {
      final s0 = pcm[start + i] / 32768 + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return (s1 * s1 + s2 * s2 - coeff * s1 * s2) / (block * block);
  }

  int at(double seconds) => (seconds * sampleRate).round();
  double medianPower(double fromSeconds, double toSeconds) {
    final values = <double>[
      for (var i = at(fromSeconds); i < at(toSeconds); i += step) power(i),
    ]..sort();
    return values[values.length ~/ 2];
  }

  final from = at(coarseSeconds - 0.06);
  final to = at(coarseSeconds + 0.04);
  if (at(coarseSeconds - 0.1) < 0 ||
      at(coarseSeconds + 0.09) + block >= pcm.length) {
    return coarseSeconds;
  }
  final level = medianPower(coarseSeconds + 0.03, coarseSeconds + 0.09);
  final noise = medianPower(coarseSeconds - 0.1, coarseSeconds - 0.06);
  final threshold = math.max(level * 0.04, noise * 4);
  if (!(threshold < level * 0.5)) return coarseSeconds;

  for (var i = from; i <= to; i += step) {
    var held = true;
    for (var h = 0; h < hold && held; h++) {
      held = power(i + h * step) >= threshold;
    }
    if (held) return (i + block / 2) / sampleRate;
  }
  return coarseSeconds;
}
