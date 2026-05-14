import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/providers/timer_provider.dart';

void main() {
  group('computeDelay', () {
    test('instant mode returns 0', () {
      const s = AppSettings(delayMode: DelayMode.instant);
      expect(TimerNotifier.computeDelay(s), 0);
    });

    test('fixed mode returns configured value', () {
      const s = AppSettings(
        delayMode: DelayMode.fixed,
        fixedDelayMs: 1500,
      );
      expect(TimerNotifier.computeDelay(s), 1500);
    });

    test('fixed mode floors negatives at 0', () {
      const s = AppSettings(
        delayMode: DelayMode.fixed,
        fixedDelayMs: -200,
      );
      expect(TimerNotifier.computeDelay(s), 0);
    });

    test('random mode is within [min, max] inclusive', () {
      const s = AppSettings(
        delayMode: DelayMode.random,
        randomDelayMinMs: 1000,
        randomDelayMaxMs: 3000,
      );
      final rng = math.Random(42);
      for (var i = 0; i < 200; i++) {
        final v = TimerNotifier.computeDelay(s, rng: rng);
        expect(v, inInclusiveRange(1000, 3000));
      }
    });

    test('random with min == max is deterministic', () {
      const s = AppSettings(
        delayMode: DelayMode.random,
        randomDelayMinMs: 2000,
        randomDelayMaxMs: 2000,
      );
      expect(TimerNotifier.computeDelay(s), 2000);
    });

    test('random with reversed range is normalized', () {
      const s = AppSettings(
        delayMode: DelayMode.random,
        randomDelayMinMs: 3000,
        randomDelayMaxMs: 1000,
      );
      // max gets clamped up to min — so result is exactly min.
      expect(TimerNotifier.computeDelay(s), 3000);
    });
  });
}
