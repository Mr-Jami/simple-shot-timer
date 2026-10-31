// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;

/// The longest stretch of a clip that is analysed at once. Longer clips go
/// through Choose the part first.
const int maxClipPartMs = 3 * 60 * 1000;

bool needsPart(int durationMs) => durationMs > maxClipPartMs;

/// The stretch of a long clip that is analysed and edited, in clip
/// milliseconds: between [minLengthMs] and [maxClipPartMs] long and always
/// inside the clip.
class PartWindow {
  const PartWindow(this.startMs, this.endMs);

  /// The opening of a clip [durationMs] long.
  factory PartWindow.first(int durationMs) =>
      PartWindow(0, math.min(durationMs, maxClipPartMs));

  /// A [lengthMs] stretch around the loudest burst in the loudness scan
  /// ([bucketMs] per value). First the stretch with the most sound energy
  /// (squaring favours bursts of shots over steady wind or talk of the same
  /// average level; ties go to the earliest), then centred on where its
  /// energy peaks: talk before or after a string would otherwise pull the
  /// string to an edge, or the beep out.
  factory PartWindow.loudest(
    List<double> loudness, {
    required int bucketMs,
    required int durationMs,
    int lengthMs = maxClipPartMs,
  }) {
    final length = math.min(lengthMs, durationMs);
    final n = math.max(1, length ~/ bucketMs);
    if (loudness.length <= n) return PartWindow(0, length);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += loudness[i] * loudness[i];
    }
    var best = sum;
    var bestAt = 0;
    for (var i = n; i < loudness.length; i++) {
      sum += loudness[i] * loudness[i] - loudness[i - n] * loudness[i - n];
      // A margin, so rounding never moves the window between equal sums.
      if (sum > best + 1e-9) {
        best = sum;
        bestAt = i - n + 1;
      }
    }
    // Weighted by energy squared, so the shots outweigh the noise.
    var weight = 0.0;
    var moment = 0.0;
    for (var i = bestAt; i < bestAt + n; i++) {
      final e = loudness[i] * loudness[i];
      weight += e * e;
      moment += e * e * i;
    }
    final centre = weight > 0 ? moment / weight : bestAt + (n - 1) / 2;
    final start = ((centre + 0.5) * bucketMs - length / 2)
        .round()
        .clamp(0, durationMs - length);
    return PartWindow(start, start + length);
  }

  /// A full-length part with a saved string ([fromMs] START to [toMs] last
  /// shot) in the middle, to reopen it without asking. A string longer
  /// than a part keeps its start.
  factory PartWindow.around(int fromMs, int toMs, {required int durationMs}) {
    final length = math.min(maxClipPartMs, durationMs);
    final start = toMs - fromMs > length - 2 * _lead
        ? fromMs - _lead
        : (fromMs + toMs) ~/ 2 - length ~/ 2;
    final clamped = start.clamp(0, durationMs - length);
    return PartWindow(clamped, clamped + length);
  }

  static const int minLengthMs = 10000;

  /// Room before START when a string barely fits.
  static const int _lead = 5000;

  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;

  /// Moved by [deltaMs] and kept inside a clip [durationMs] long.
  PartWindow movedBy(int deltaMs, int durationMs) {
    final start = (startMs + deltaMs).clamp(0, durationMs - lengthMs);
    return PartWindow(start, start + lengthMs);
  }

  /// With its start dragged to [ms]; the end stays.
  PartWindow withStart(int ms) => PartWindow(
        ms.clamp(math.max(0, endMs - maxClipPartMs), endMs - minLengthMs),
        endMs,
      );

  /// With its end dragged to [ms]; the start stays.
  PartWindow withEnd(int ms, int durationMs) => PartWindow(
        startMs,
        ms.clamp(startMs + minLengthMs,
            math.min(durationMs, startMs + maxClipPartMs)),
      );

  @override
  bool operator ==(Object other) =>
      other is PartWindow && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'PartWindow($startMs..$endMs)';
}
