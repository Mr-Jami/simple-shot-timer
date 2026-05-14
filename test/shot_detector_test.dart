import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/app_settings.dart';

void main() {
  group('AppSettings.detectionThreshold', () {
    test('100% sensitivity → threshold 0 (catch everything)', () {
      const s = AppSettings(sensitivityPercent: 100);
      expect(s.detectionThreshold, 0.0);
    });

    test('0% sensitivity → threshold 1 (nothing crosses)', () {
      const s = AppSettings(sensitivityPercent: 0);
      expect(s.detectionThreshold, 1.0);
    });

    test('50% sensitivity → threshold 0.5', () {
      const s = AppSettings(sensitivityPercent: 50);
      expect(s.detectionThreshold, closeTo(0.5, 1e-9));
    });

    test('values outside 0..100 are clamped', () {
      expect(
        const AppSettings(sensitivityPercent: -50).detectionThreshold,
        1.0,
      );
      expect(
        const AppSettings(sensitivityPercent: 250).detectionThreshold,
        0.0,
      );
    });
  });
}
