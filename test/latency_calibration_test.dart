import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/providers/timer_provider.dart';

void main() {
  group('TimerNotifier.calibrateBase', () {
    test('rebases t=0 onto the audible onset (no manual offset)', () {
      final r = TimerNotifier.calibrateBase(
        requestMs: 1000,
        onsetMs: 1350,
        manualOffsetMs: 0,
        maxPlausibleLatencyMs: 700,
      );
      expect(r, isNotNull);
      expect(r!.latencyMs, 350);
      expect(r.newBaseMs, 1350);
    });

    test('manual offset pushes the base later, so shots read lower', () {
      final r = TimerNotifier.calibrateBase(
        requestMs: 1000,
        onsetMs: 1350,
        manualOffsetMs: 80,
        maxPlausibleLatencyMs: 700,
      );
      expect(r, isNotNull);
      expect(r!.newBaseMs, 1430);
    });

    test('implausibly large latency is rejected (keep provisional base)', () {
      final r = TimerNotifier.calibrateBase(
        requestMs: 1000,
        onsetMs: 2000, // 1000 ms latency
        manualOffsetMs: 0,
        maxPlausibleLatencyMs: 700,
      );
      expect(r, isNull);
    });

    test('negative latency (onset before the request) is rejected', () {
      final r = TimerNotifier.calibrateBase(
        requestMs: 1000,
        onsetMs: 980,
        manualOffsetMs: 0,
        maxPlausibleLatencyMs: 700,
      );
      expect(r, isNull);
    });

    test('latency exactly at the ceiling is accepted', () {
      final r = TimerNotifier.calibrateBase(
        requestMs: 0,
        onsetMs: 700,
        manualOffsetMs: 0,
        maxPlausibleLatencyMs: 700,
      );
      expect(r, isNotNull);
      expect(r!.latencyMs, 700);
    });
  });
}
