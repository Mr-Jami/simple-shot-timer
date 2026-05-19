import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/biquad_notch.dart';

void main() {
  const sampleRate = 44100.0;
  const beepHz = 2325.0;

  Int16List sine(double freqHz, int durationMs, {double amplitude = 0.9}) {
    final n = (sampleRate * durationMs / 1000).round();
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      final v = math.sin(2 * math.pi * freqHz * i / sampleRate) * amplitude;
      out[i] = (v * 32767).round();
    }
    return out;
  }

  int peakAbs(Int16List samples, {int skip = 0}) {
    var p = 0;
    for (var i = skip; i < samples.length; i++) {
      final a = samples[i] < 0 ? -samples[i] : samples[i];
      if (a > p) p = a;
    }
    return p;
  }

  test('attenuates the beep tone by >20 dB after settling', () {
    final filter = BiquadNotch(
      sampleRate: sampleRate,
      frequencyHz: beepHz,
      q: 10,
    );
    final tone = sine(beepHz, 300);
    final originalPeak = peakAbs(tone);
    filter.processInt16InPlace(tone);
    // Skip the first 5 ms — the IIR needs a few cycles to converge from zero
    // state and shows a brief envelope spike before settling into the notch.
    final residualPeak = peakAbs(tone, skip: (sampleRate * 0.005).round());
    final attenuationDb = 20 * math.log(residualPeak / originalPeak) / math.ln10;
    expect(attenuationDb, lessThan(-20),
        reason: 'expected >20 dB rejection, got ${attenuationDb.toStringAsFixed(1)} dB');
  });

  test('passes a broadband impulse with most of its peak intact', () {
    final filter = BiquadNotch(
      sampleRate: sampleRate,
      frequencyHz: beepHz,
      q: 10,
    );
    // 50 ms of silence with a single full-scale spike in the middle —
    // approximates the impulsive transient of a gunshot for filter analysis.
    final n = (sampleRate * 0.05).round();
    final impulse = Int16List(n);
    impulse[n ~/ 2] = 32000;
    filter.processInt16InPlace(impulse);
    final peak = peakAbs(impulse);
    // A narrow notch should preserve the bulk of an impulse's peak. We allow
    // a generous margin — even substantial coefficient ringing should still
    // leave >70% of the original peak intact.
    expect(peak, greaterThan(22000),
        reason: 'broadband impulse should pass through; peak was $peak');
  });

  test('attenuates the beep more than it attenuates a nearby off-band tone', () {
    final filter1 = BiquadNotch(
      sampleRate: sampleRate,
      frequencyHz: beepHz,
      q: 10,
    );
    final filter2 = BiquadNotch(
      sampleRate: sampleRate,
      frequencyHz: beepHz,
      q: 10,
    );
    final onBand = sine(beepHz, 300);
    final offBand = sine(1000, 300);
    filter1.processInt16InPlace(onBand);
    filter2.processInt16InPlace(offBand);
    final skip = (sampleRate * 0.01).round();
    expect(peakAbs(onBand, skip: skip),
        lessThan(peakAbs(offBand, skip: skip) ~/ 4));
  });
}
