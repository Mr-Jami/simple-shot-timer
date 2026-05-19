import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/biquad.dart';

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
    final filter = Biquad.notch(
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
    final filter = Biquad.notch(
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
    final filter1 = Biquad.notch(
      sampleRate: sampleRate,
      frequencyHz: beepHz,
      q: 10,
    );
    final filter2 = Biquad.notch(
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

  group('bandpass cascade (HPF + LPF)', () {
    // Mimics ShotDetector's bandpass: a Butterworth-Q HPF at 300 Hz then a
    // Butterworth-Q LPF at 6 kHz. The tests assert the response across the
    // band: rumble killed, pass band passes, hiss killed.
    Biquad newHpf() =>
        Biquad.highpass(sampleRate: sampleRate, cutoffHz: 300);
    Biquad newLpf() =>
        Biquad.lowpass(sampleRate: sampleRate, cutoffHz: 6000);

    int filteredPeakAt(double freqHz) {
      final hpf = newHpf();
      final lpf = newLpf();
      final s = sine(freqHz, 300);
      hpf.processInt16InPlace(s);
      lpf.processInt16InPlace(s);
      // Skip ~20 ms of settling — both filters need a few cycles to clear
      // their startup transient from zero state.
      return peakAbs(s, skip: (sampleRate * 0.02).round());
    }

    // 12 dB/octave biquad: ~1.5 octaves below the 300 Hz HPF cutoff gives
    // roughly -15 to -20 dB. Anything in that range means the rumble band is
    // meaningfully suppressed before peak detection.
    test('rumble (100 Hz) is attenuated >15 dB', () {
      final original = peakAbs(sine(100, 300));
      final filtered = filteredPeakAt(100);
      final dB = 20 * math.log(filtered / original) / math.ln10;
      expect(dB, lessThan(-15),
          reason: 'expected >15 dB cut at 100 Hz, got ${dB.toStringAsFixed(1)} dB');
    });

    test('passband (2 kHz) passes within 3 dB', () {
      final original = peakAbs(sine(2000, 300));
      final filtered = filteredPeakAt(2000);
      final dB = 20 * math.log(filtered / original) / math.ln10;
      expect(dB, greaterThan(-3),
          reason: 'expected <3 dB cut at 2 kHz, got ${dB.toStringAsFixed(1)} dB');
    });

    // 12 kHz sits 1 octave above the 6 kHz LPF cutoff — 12 dB/octave plus
    // the cutoff itself's -3 dB gives ~-15 dB in theory.
    test('hiss (12 kHz) is attenuated >12 dB', () {
      final original = peakAbs(sine(12000, 300));
      final filtered = filteredPeakAt(12000);
      final dB = 20 * math.log(filtered / original) / math.ln10;
      expect(dB, lessThan(-12),
          reason: 'expected >12 dB cut at 12 kHz, got ${dB.toStringAsFixed(1)} dB');
    });
  });
}
