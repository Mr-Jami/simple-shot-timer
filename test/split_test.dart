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
}
