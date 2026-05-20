import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';

TimerString _string(List<int> timesMs, {int penalty = 0}) => TimerString(
      createdAt: DateTime(2026, 1, 1),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      penaltyMs: penalty,
      shots: [
        for (var i = 0; i < timesMs.length; i++)
          Shot(index: i, timeMs: timesMs[i]),
      ],
    );

void main() {
  group('TimerString summary', () {
    test('empty string has zero totals and null splits', () {
      final s = _string(const []);
      expect(s.totalTimeMs, 0);
      expect(s.firstShotMs, isNull);
      expect(s.fastestSplitMs, isNull);
      expect(s.slowestSplitMs, isNull);
      expect(s.averageSplitMs, isNull);
      expect(s.splitsMs, isEmpty);
    });

    test('single shot has no splits', () {
      final s = _string([500]);
      expect(s.firstShotMs, 500);
      expect(s.totalTimeMs, 500);
      expect(s.splitsMs, isEmpty);
      expect(s.fastestSplitMs, isNull);
    });

    test('multi-shot splits are correctly computed', () {
      final s = _string([500, 800, 1100, 1500]);
      expect(s.splitsMs, [300, 300, 400]);
      expect(s.fastestSplitMs, 300);
      expect(s.slowestSplitMs, 400);
      expect(s.averageSplitMs, (300 + 300 + 400) ~/ 3);
      expect(s.totalTimeMs, 1500);
      expect(s.firstShotMs, 500);
    });

    test('penalty adds to total time', () {
      final s = _string([1000, 2000], penalty: 500);
      expect(s.totalTimeMs, 2500);
    });
  });

  group('TimerString per-cycle aggregates', () {
    // Two-cycle string: cycle 1 has shots at 500/1000ms, cycle 2 at 400/900ms.
    // Both cycles start their clock from 0, so timeMs values look small even
    // for the second cycle.
    TimerString multi() => TimerString(
          createdAt: DateTime(2026, 1, 1),
          drillMode: DrillMode.par,
          delayMode: DelayMode.instant,
          delayUsedMs: 0,
          pars: const [],
          shots: [
            Shot(index: 0, timeMs: 500, cycleIndex: 1),
            Shot(index: 1, timeMs: 1000, cycleIndex: 1),
            Shot(index: 2, timeMs: 400, cycleIndex: 2),
            Shot(index: 3, timeMs: 900, cycleIndex: 2),
          ],
        );

    test('cyclesWithShots returns each populated cycle in order', () {
      expect(multi().cyclesWithShots, [1, 2]);
    });

    test('shotsForCycle filters by cycle index', () {
      final s = multi();
      expect(s.shotsForCycle(1).map((x) => x.timeMs), [500, 1000]);
      expect(s.shotsForCycle(2).map((x) => x.timeMs), [400, 900]);
    });

    test('splitsForCycle stays within the cycle', () {
      final s = multi();
      expect(s.splitsForCycle(1), [500]);
      expect(s.splitsForCycle(2), [500]);
    });

    test('totalForCycle returns the last shot time in that cycle', () {
      final s = multi();
      expect(s.totalForCycle(1), 1000);
      expect(s.totalForCycle(2), 900);
    });

    test('flat splitsMs never crosses cycles', () {
      // Without per-cycle filtering this would emit -600 between cycle 1's
      // last shot (1000ms) and cycle 2's first (400ms), which is meaningless.
      expect(multi().splitsMs, [500, 500]);
    });
  });
}
