import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/par_schedule.dart';

void main() {
  group('computeParSchedule', () {
    test('standard mode produces no events', () {
      const s = AppSettings();
      expect(computeParSchedule(s, DrillMode.standard), isEmpty);
    });

    test('par single repeat: one end beep at parDuration', () {
      const s = AppSettings(parDurationMs: 2000, parRepeatCount: 1);
      final events = computeParSchedule(s, DrillMode.par);
      expect(events, hasLength(1));
      expect(events.single.timeMs, 2000);
      expect(events.single.kind, ParBeepKind.end);
      expect(events.single.cycle, 1);
    });

    test('par 0ms duration produces no events', () {
      const s = AppSettings(parDurationMs: 0, parRepeatCount: 3);
      expect(computeParSchedule(s, DrillMode.par), isEmpty);
    });

    test('par with interval=0 fires back-to-back ends only (legacy)', () {
      const s = AppSettings(
        parDurationMs: 2000,
        parRepeatCount: 4,
        parIntervalMs: 0,
      );
      final events = computeParSchedule(s, DrillMode.par);
      // 4 ends at 2s, 4s, 6s, 8s. No explicit start beeps because the
      // previous end beep doubles as the next window's start.
      expect(events.map((e) => e.timeMs), [2000, 4000, 6000, 8000]);
      expect(events.every((e) => e.kind == ParBeepKind.end), isTrue);
      expect(events.map((e) => e.cycle), [1, 2, 3, 4]);
    });

    test('par with interval>0 fires start+end for cycles 2..N', () {
      const s = AppSettings(
        parDurationMs: 2000,
        parRepeatCount: 4,
        parIntervalMs: 5000,
      );
      final events = computeParSchedule(s, DrillMode.par);
      // Cycle 1: end only at 2s (master start covers t=0).
      // Cycle 2: start at 7s, end at 9s.
      // Cycle 3: start at 14s, end at 16s.
      // Cycle 4: start at 21s, end at 23s.
      expect(
        events
            .map((e) => '${e.kind.name}@${e.timeMs}c${e.cycle}')
            .toList(),
        [
          'end@2000c1',
          'start@7000c2',
          'end@9000c2',
          'start@14000c3',
          'end@16000c3',
          'start@21000c4',
          'end@23000c4',
        ],
      );
    });

    test('par negative interval is treated as zero', () {
      const s = AppSettings(
        parDurationMs: 2000,
        parRepeatCount: 3,
        parIntervalMs: -1000,
      );
      final events = computeParSchedule(s, DrillMode.par);
      expect(events.map((e) => e.timeMs), [2000, 4000, 6000]);
      expect(events.every((e) => e.kind == ParBeepKind.end), isTrue);
    });

    test('par repeat clamps to AppSettings.parRepeatMax', () {
      const s = AppSettings(
        parDurationMs: 1000,
        parRepeatCount: 9999,
        parIntervalMs: 0,
      );
      final events = computeParSchedule(s, DrillMode.par);
      expect(events, hasLength(AppSettings.parRepeatMax));
    });

    test('stage produces a single end beep at stageDurationMs', () {
      const s = AppSettings(stageDurationMs: 120000);
      final events = computeParSchedule(s, DrillMode.stage);
      expect(events, hasLength(1));
      expect(events.single.timeMs, 120000);
      expect(events.single.kind, ParBeepKind.end);
      expect(events.single.cycle, 1);
    });

    test('stage with 0 duration produces no events', () {
      const s = AppSettings(stageDurationMs: 0);
      expect(computeParSchedule(s, DrillMode.stage), isEmpty);
    });
  });
}
