import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/calibration_shot.dart';
import 'package:simple_shot_timer/services/auto_configure.dart';
import 'package:simple_shot_timer/utils/fft.dart';

CalibrationShot shot({
  required double peak,
  required double lowHz,
  required double highHz,
  double dominantHz = 1000,
}) =>
    CalibrationShot(
      peakAmplitude: peak,
      lowEdgeHz: lowHz,
      highEdgeHz: highHz,
      dominantHz: dominantHz,
    );

void main() {
  group('isolateShotCluster', () {
    test('returns input unchanged when fewer than 4 captures', () {
      final list = [
        shot(peak: 0.2, lowHz: 500, highHz: 4000),
        shot(peak: 0.9, lowHz: 500, highHz: 4000),
      ];
      expect(isolateShotCluster(list), list);
    });

    test('drops quiet background noise below the loudness gap', () {
      final noise1 = shot(peak: 0.15, lowHz: 300, highHz: 1200);
      final noise2 = shot(peak: 0.22, lowHz: 300, highHz: 1200);
      final s1 = shot(peak: 0.88, lowHz: 500, highHz: 5000);
      final s2 = shot(peak: 0.93, lowHz: 500, highHz: 5000);
      final s3 = shot(peak: 0.99, lowHz: 500, highHz: 5000);
      final cluster = isolateShotCluster([noise1, s1, noise2, s3, s2]);
      expect(cluster.length, 3);
      expect(cluster, containsAll([s1, s2, s3]));
      expect(cluster, isNot(contains(noise1)));
      expect(cluster, isNot(contains(noise2)));
    });

    test('keeps all captures when they are uniformly loud', () {
      final list = [
        shot(peak: 0.90, lowHz: 500, highHz: 5000),
        shot(peak: 0.93, lowHz: 500, highHz: 5000),
        shot(peak: 0.96, lowHz: 500, highHz: 5000),
        shot(peak: 1.00, lowHz: 500, highHz: 5000),
      ];
      expect(isolateShotCluster(list).length, 4);
    });

    test('drops a loud-but-spectrally-alien event', () {
      // All similarly loud (no loudness gap), but one sits at 200 Hz while the
      // rest cluster around 1500 Hz — a door slam among muzzle cracks.
      final thump = shot(peak: 0.95, lowHz: 80, highHz: 300, dominantHz: 200);
      final list = [
        thump,
        shot(peak: 0.92, lowHz: 800, highHz: 5000, dominantHz: 1500),
        shot(peak: 0.96, lowHz: 800, highHz: 5000, dominantHz: 1500),
        shot(peak: 1.00, lowHz: 800, highHz: 5000, dominantHz: 1500),
      ];
      final cluster = isolateShotCluster(list);
      expect(cluster, isNot(contains(thump)));
      expect(cluster.length, 3);
    });
  });

  group('suggestFromSelected', () {
    test('returns null on empty selection', () {
      expect(suggestFromSelected(const [], totalCaptured: 5), isNull);
    });

    test('uses the explicit selection without re-clustering', () {
      // A quiet capture is included by the user deliberately — it widens the
      // selection but the median still dominates.
      final s = suggestFromSelected(
        [
          shot(peak: 0.30, lowHz: 500, highHz: 4000),
          shot(peak: 0.90, lowHz: 500, highHz: 4000),
        ],
        totalCaptured: 6,
      )!;
      // sorted peaks [0.30, 0.90] → median 0.90 → threshold 0.855 → sensitivity ≈ 14
      expect(s.sensitivityPercent, closeTo(14, 2));
      expect(s.consideredCount, 2);
      expect(s.shotCount, 6);
    });
  });

  group('suggestFromShots', () {
    test('returns null when no shots were captured', () {
      expect(suggestFromShots(const []), isNull);
    });

    test('sensitivity is set so the median shot crosses with a tight margin', () {
      final s = suggestFromShots([
        shot(peak: 0.40, lowHz: 500, highHz: 4000),
        shot(peak: 0.80, lowHz: 500, highHz: 4000),
        shot(peak: 0.60, lowHz: 500, highHz: 4000),
      ])!;
      // sorted [0.40, 0.60, 0.80] → median 0.60 → threshold 0.57 → sensitivity = 43
      expect(s.sensitivityPercent, 43);
    });

    test('band spans the widest observed range with 20% padding', () {
      final s = suggestFromShots([
        shot(peak: 0.7, lowHz: 400, highHz: 5000),
        shot(peak: 0.7, lowHz: 300, highHz: 6000),
        shot(peak: 0.7, lowHz: 500, highHz: 4500),
      ])!;
      // min low = 300 * 0.8 = 240 → snap to 250
      expect(s.bandLowHz, 250);
      // max high = 6000 * 1.2 = 7200 → snap to 7200
      expect(s.bandHighHz, 7200);
    });

    test('band is clamped to slider limits', () {
      final s = suggestFromShots([
        shot(peak: 0.7, lowHz: 30, highHz: 15000),
      ])!;
      expect(s.bandLowHz, greaterThanOrEqualTo(50));
      expect(s.bandHighHz, lessThanOrEqualTo(12000));
    });

    test('always leaves at least 500 Hz of passband', () {
      final s = suggestFromShots([
        shot(peak: 0.7, lowHz: 1800, highHz: 1850),
      ])!;
      expect(s.bandHighHz - s.bandLowHz, greaterThanOrEqualTo(500));
    });

    test('sensitivity ignores quiet background noise', () {
      // Two quiet non-shots + three loud shots. Without clustering the
      // median (0.88) would still be the loudest-shot cluster median anyway,
      // but the clustering keeps quiet captures from dragging it down. After
      // clustering, only the loud shots count: median 0.94 → threshold
      // 0.893 → sensitivity ≈ 11.
      final s = suggestFromShots([
        shot(peak: 0.18, lowHz: 300, highHz: 1200),
        shot(peak: 0.24, lowHz: 300, highHz: 1200),
        shot(peak: 0.88, lowHz: 500, highHz: 5000),
        shot(peak: 0.94, lowHz: 500, highHz: 5000),
        shot(peak: 0.99, lowHz: 500, highHz: 5000),
      ])!;
      expect(s.consideredCount, 3);
      expect(s.shotCount, 5);
      expect(s.sensitivityPercent, closeTo(11, 2));
    });

    test('band ignores noise sitting outside the shot band', () {
      // Low-frequency noise (80–400 Hz) should not widen the band downward
      // once it's clustered out.
      final s = suggestFromShots([
        shot(peak: 0.15, lowHz: 80, highHz: 400),
        shot(peak: 0.20, lowHz: 80, highHz: 400),
        shot(peak: 0.90, lowHz: 600, highHz: 5000),
        shot(peak: 0.95, lowHz: 600, highHz: 5000),
        shot(peak: 1.00, lowHz: 600, highHz: 5000),
      ])!;
      // 600 * 0.8 = 480 → snapped to 500, well above the noise floor of 80.
      expect(s.bandLowHz, greaterThanOrEqualTo(450));
    });
  });

  group('spectralBand', () {
    const sampleRate = 44100.0;

    Float64List sine(double freqHz, int n, {double amplitude = 0.9}) {
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = math.sin(2 * math.pi * freqHz * i / sampleRate) * amplitude;
      }
      return out;
    }

    test('returns null on silent input', () {
      final band = spectralBand(
        samples: Float64List(2048),
        sampleRate: sampleRate,
      );
      expect(band, isNull);
    });

    test('pure 2 kHz tone collapses low and high edges around 2 kHz', () {
      final band = spectralBand(
        samples: sine(2000, 2048),
        sampleRate: sampleRate,
      )!;
      // All energy is at 2 kHz, so the 10/90 percentiles should sit on or
      // adjacent to that bin (binHz at N=2048 is ~21.5 Hz, plus window leakage).
      expect(band.dominantHz, closeTo(2000, 50));
      expect(band.lowEdgeHz, closeTo(2000, 100));
      expect(band.highEdgeHz, closeTo(2000, 100));
    });

    test('two-tone signal sets edges around the constituent tones', () {
      final n = 2048;
      final a = sine(800, n);
      final b = sine(4000, n);
      final mix = Float64List(n);
      for (var i = 0; i < n; i++) {
        mix[i] = (a[i] + b[i]) / 2;
      }
      final band = spectralBand(samples: mix, sampleRate: sampleRate)!;
      expect(band.lowEdgeHz, lessThan(1500));
      expect(band.highEdgeHz, greaterThan(3000));
    });
  });
}
