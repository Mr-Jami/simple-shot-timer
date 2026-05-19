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
  group('suggestFromShots', () {
    test('returns null when no shots were captured', () {
      expect(suggestFromShots(const []), isNull);
    });

    test('sensitivity is set so the quietest shot crosses with margin', () {
      final s = suggestFromShots([
        shot(peak: 0.40, lowHz: 500, highHz: 4000),
        shot(peak: 0.80, lowHz: 500, highHz: 4000),
        shot(peak: 0.60, lowHz: 500, highHz: 4000),
      ])!;
      // Threshold = 0.40 * 0.75 = 0.30 → sensitivity = 70
      expect(s.sensitivityPercent, 70);
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
