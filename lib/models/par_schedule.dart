import 'dart:math' as math;

import 'app_settings.dart';
import 'enums.dart';

enum ParBeepKind { start, end }

class ParBeepEvent {
  const ParBeepEvent({
    required this.timeMs,
    required this.kind,
    required this.cycle,
  });

  /// Clock-relative time (ms) measured from the master start beep at t=0.
  final int timeMs;
  final ParBeepKind kind;

  /// 1-based cycle index this event belongs to.
  final int cycle;
}

/// Pure computation of the par-beep schedule for a given drill snapshot.
///
/// Standard → no events. Stage → one [ParBeepKind.end] at `stageDurationMs`.
/// Par → for each cycle i = 1..N at offset `(i-1) * (durMs + interval)`,
/// emit a [ParBeepKind.start] at the cycle's start when i > 1 AND interval > 0
/// (otherwise the previous cycle's end beep doubles as the new start), and
/// always a [ParBeepKind.end] at start + durMs.
List<ParBeepEvent> computeParSchedule(AppSettings s, DrillMode mode) {
  switch (mode) {
    case DrillMode.standard:
      return const [];
    case DrillMode.stage:
      final dur = s.stageDurationMs;
      if (dur <= 0) return const [];
      return [ParBeepEvent(timeMs: dur, kind: ParBeepKind.end, cycle: 1)];
    case DrillMode.par:
      final dur = s.parDurationMs;
      if (dur <= 0) return const [];
      final count = s.parRepeatCount.clamp(1, AppSettings.parRepeatMax);
      final interval = math.max(0, s.parIntervalMs);
      final events = <ParBeepEvent>[];
      for (var i = 1; i <= count; i++) {
        final cycleStartMs = (i - 1) * (dur + interval);
        final endAtMs = cycleStartMs + dur;
        if (i > 1 && interval > 0) {
          events.add(ParBeepEvent(
            timeMs: cycleStartMs,
            kind: ParBeepKind.start,
            cycle: i,
          ));
        }
        events.add(ParBeepEvent(
          timeMs: endAtMs,
          kind: ParBeepKind.end,
          cycle: i,
        ));
      }
      return events;
  }
}
