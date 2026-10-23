// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/part_window.dart';

void main() {
  const minute = 60 * 1000;
  const tenMinutes = 10 * minute;

  test('only clips over three minutes need a part', () {
    expect(needsPart(maxClipPartMs), isFalse);
    expect(needsPart(maxClipPartMs + 1), isTrue);
  });

  test('starts at the beginning', () {
    expect(PartWindow.first(tenMinutes), const PartWindow(0, maxClipPartMs));
  });

  group('the loudest stretch', () {
    List<double> levels(int minutes, Map<int, double> loud) => [
          for (var i = 0; i < minutes * 240; i++) loud[i ~/ 240] ?? 0.02,
        ];

    test('holds the burst of shots', () {
      // Minute 6 is loud.
      final w = PartWindow.loudest(levels(10, {6: 0.4}),
          bucketMs: 250, durationMs: tenMinutes);
      expect(w.lengthMs, maxClipPartMs);
      expect(w.startMs, lessThanOrEqualTo(6 * minute));
      expect(w.endMs, greaterThanOrEqualTo(7 * minute));
    });

    test('prefers shots over longer, steadier noise', () {
      // Three minutes of wind at 0.1 against 20 s of shots at 0.4: the
      // wind sums to more than twice as much, the shots to far more energy.
      final scan = [
        for (var i = 0; i < 10 * 240; i++)
          i < 3 * 240
              ? 0.1
              : i >= 8 * 240 && i < 8 * 240 + 80
                  ? 0.4
                  : 0.0,
      ];
      final w = PartWindow.loudest(scan, bucketMs: 250, durationMs: tenMinutes);
      expect(w.startMs, greaterThan(5 * minute));
    });

    test('stays inside the clip and keeps to the first on a tie', () {
      final quiet = levels(10, {});
      expect(PartWindow.loudest(quiet, bucketMs: 250, durationMs: tenMinutes),
          const PartWindow(0, maxClipPartMs));
      final atEnd = PartWindow.loudest(levels(10, {9: 0.5}),
          bucketMs: 250, durationMs: tenMinutes);
      expect(atEnd.endMs, tenMinutes);
    });

    test('of a partial scan, as far as it got', () {
      final w =
          PartWindow.loudest([0.1, 0.2], bucketMs: 250, durationMs: tenMinutes);
      expect(w, const PartWindow(0, maxClipPartMs));
    });
  });

  group('around a saved string', () {
    test('puts it in the middle', () {
      final w = PartWindow.around(5 * minute, 5 * minute + 20000,
          durationMs: tenMinutes);
      expect(w.lengthMs, maxClipPartMs);
      expect(w.startMs + w.lengthMs ~/ 2, 5 * minute + 10000);
    });

    test('keeps inside the clip near its ends', () {
      expect(PartWindow.around(1000, 9000, durationMs: tenMinutes).startMs, 0);
      expect(
          PartWindow.around(tenMinutes - 5000, tenMinutes - 1000,
                  durationMs: tenMinutes)
              .endMs,
          tenMinutes);
    });

    test('a string longer than a part keeps its start', () {
      final w = PartWindow.around(minute, minute + maxClipPartMs,
          durationMs: tenMinutes);
      expect(w.startMs, minute - 5000);
      expect(w.lengthMs, maxClipPartMs);
    });
  });

  group('dragging', () {
    const w = PartWindow(2 * minute, 4 * minute);

    test('moves the whole window, stopping at the ends', () {
      expect(w.movedBy(30000, tenMinutes),
          const PartWindow(2 * minute + 30000, 4 * minute + 30000));
      expect(
          w.movedBy(-10 * minute, tenMinutes), const PartWindow(0, 2 * minute));
      expect(w.movedBy(10 * minute, tenMinutes),
          const PartWindow(8 * minute, tenMinutes));
    });

    test('an edge resizes it, never past three minutes or under ten seconds',
        () {
      expect(w.withStart(minute + 30000).startMs, minute + 30000);
      expect(w.withStart(0).startMs, minute);
      expect(w.withStart(4 * minute).lengthMs, PartWindow.minLengthMs);
      expect(w.withEnd(9 * minute, tenMinutes).endMs, 5 * minute);
      expect(w.withEnd(0, tenMinutes).lengthMs, PartWindow.minLengthMs);
      expect(
          const PartWindow(8 * minute, 9 * minute)
              .withEnd(20 * minute, tenMinutes)
              .endMs,
          tenMinutes);
    });
  });
}
