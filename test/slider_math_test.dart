import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/utils/slider_math.dart';

void main() {
  group('clampToStep', () {
    test('rounds to the nearest step multiple', () {
      expect(clampToStep(2440, min: 0, max: 10000, step: 100), 2400);
      expect(clampToStep(2450, min: 0, max: 10000, step: 100), 2500);
      expect(clampToStep(2460, min: 0, max: 10000, step: 100), 2500);
    });

    test('clamps below min and above max', () {
      expect(clampToStep(-500, min: 0, max: 10000, step: 100), 0);
      expect(clampToStep(99999, min: 0, max: 10000, step: 100), 10000);
      // parDuration range: min itself is not a step multiple concern here,
      // but the clamp must still hold it.
      expect(clampToStep(0, min: 100, max: 30000, step: 100), 100);
    });
  });

  group('clampToStepDouble', () {
    test('snaps beep volume to 0.05 steps within 0..1', () {
      expect(clampToStepDouble(0.87, min: 0, max: 1, step: 0.05),
          closeTo(0.85, 1e-9));
      expect(clampToStepDouble(1.2, min: 0, max: 1, step: 0.05), 1.0);
      expect(clampToStepDouble(-0.3, min: 0, max: 1, step: 0.05), 0.0);
    });
  });

  group('softSnap', () {
    int snap(num raw) =>
        softSnap(raw, min: 0, max: 10000, step: 100, magnet: 500);

    test('values on a magnet multiple stay put', () {
      expect(snap(2500), 2500);
      expect(snap(3000), 3000);
      expect(snap(0), 0);
    });

    test('values within tolerance are pulled onto the magnet', () {
      expect(snap(2400), 2500);
      expect(snap(2600), 2500);
      expect(snap(100), 0);
      expect(snap(4900), 5000);
    });

    test('values outside tolerance keep the fine step', () {
      expect(snap(2300), 2300);
      expect(snap(2700), 2700);
      expect(snap(200), 200);
    });

    test('tolerance boundary is inclusive', () {
      expect(
        softSnap(2350, min: 0, max: 10000, step: 50, magnet: 500),
        2500,
      );
      expect(
        softSnap(2340, min: 0, max: 10000, step: 20, magnet: 500),
        2340,
      );
    });

    test('magnet target outside the range is clamped back in', () {
      // parDuration min is 100; raw 100 is pulled toward 0 but clamps to 100.
      expect(softSnap(100, min: 100, max: 30000, step: 100, magnet: 500), 100);
    });

    test('full drag pipeline: raw drag value steps then magnetizes', () {
      // 2430 -> step 100 -> 2400 -> within 150 of 2500 -> 2500.
      expect(snap(2430), 2500);
    });
  });
}
