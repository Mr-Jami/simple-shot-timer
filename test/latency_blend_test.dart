import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/providers/timer_provider.dart';

/// The flash and haptic are delayed by a learned output latency so they land
/// on the audible beep. The blend must move quickly enough to converge in a
/// few strings and slowly enough that one odd reading cannot drag it.
void main() {
  group('TimerNotifier.blendLatency', () {
    test('weights history 70/30', () {
      expect(TimerNotifier.blendLatency(60, 160), 90);
      expect(TimerNotifier.blendLatency(90, 160), 111);
    });

    test('an unchanged reading leaves the estimate alone', () {
      expect(TimerNotifier.blendLatency(120, 120), 120);
    });

    test('converges within a par string of samples', () {
      var estimate = 60;
      for (var i = 0; i < 6; i++) {
        estimate = TimerNotifier.blendLatency(estimate, 160);
      }
      expect((estimate - 160).abs(), lessThan(15));
    });

    test('one outlier moves the estimate by less than a third of the gap', () {
      final after = TimerNotifier.blendLatency(100, 700);
      expect(after - 100, lessThan(200));
    });
  });
}
