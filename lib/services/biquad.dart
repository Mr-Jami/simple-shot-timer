import 'dart:math' as math;
import 'dart:typed_data';

/// Single-section RBJ biquad filter, Direct Form I, with state preserved
/// across calls so it can be fed PCM chunks back-to-back without
/// discontinuity. One class with three factory constructors covers every
/// kind of filter the shot detector needs: notch (kill the beep tone),
/// highpass (low-cut), lowpass (high-cut). Chain instances for a bandpass.
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  /// Narrow band-reject. Use to strip a known interfering tone (e.g. the
  /// start/par beep) without touching nearby content.
  factory Biquad.notch({
    required double sampleRate,
    required double frequencyHz,
    double q = 10,
  }) {
    final w0 = 2 * math.pi * frequencyHz / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final a0 = 1 + alpha;
    return Biquad._(
      1 / a0,
      -2 * cosW0 / a0,
      1 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  /// 12 dB/octave high-pass (low-cut). Removes wind rumble, room boom, and
  /// low-frequency door-slam energy before peak detection.
  factory Biquad.highpass({
    required double sampleRate,
    required double cutoffHz,
    double q = math.sqrt1_2, // Butterworth-flat passband
  }) {
    final w0 = 2 * math.pi * cutoffHz / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 + cosW0) / 2 / a0,
      -(1 + cosW0) / a0,
      (1 + cosW0) / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  /// 12 dB/octave low-pass (high-cut). Removes hiss and high-frequency
  /// transients above the gunshot band.
  factory Biquad.lowpass({
    required double sampleRate,
    required double cutoffHz,
    double q = math.sqrt1_2,
  }) {
    final w0 = 2 * math.pi * cutoffHz / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);
    final a0 = 1 + alpha;
    final oneMinusCos = 1 - cosW0;
    return Biquad._(
      oneMinusCos / 2 / a0,
      oneMinusCos / a0,
      oneMinusCos / 2 / a0,
      -2 * cosW0 / a0,
      (1 - alpha) / a0,
    );
  }

  final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  /// Filters [samples] in place. Operates on int16 PCM in [-32768, 32767].
  /// Output is clamped back to int16 range; intermediate math is in doubles
  /// so coefficient quantization doesn't accumulate.
  void processInt16InPlace(Int16List samples) {
    for (var i = 0; i < samples.length; i++) {
      final x = samples[i].toDouble();
      final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
      _x2 = _x1;
      _x1 = x;
      _y2 = _y1;
      _y1 = y;
      final clamped = y < -32768 ? -32768 : (y > 32767 ? 32767 : y.round());
      samples[i] = clamped;
    }
  }

  /// Wipes filter state. Call when restarting the mic stream so a long pause
  /// doesn't leak old samples into the next run.
  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
