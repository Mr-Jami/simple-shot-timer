import 'dart:math' as math;
import 'dart:typed_data';

/// Single-section RBJ biquad notch filter, Direct Form I, with state preserved
/// across calls so it can be fed PCM chunks back-to-back without discontinuity.
///
/// Used by [ShotDetector] to strip the start/par beep tone (a clean ~2.3 kHz
/// sine) out of the mic stream so a shot fired during or immediately after the
/// beep still registers. A gunshot is broadband and impulsive, so a narrow
/// notch loses only a sliver of its spectrum.
class BiquadNotch {
  BiquadNotch({
    required double sampleRate,
    required double frequencyHz,
    double q = 10.0,
  }) {
    final w0 = 2 * math.pi * frequencyHz / sampleRate;
    final cosW0 = math.cos(w0);
    final alpha = math.sin(w0) / (2 * q);

    // RBJ Audio EQ Cookbook — notch (band-reject) coefficients.
    final a0 = 1 + alpha;
    _b0 = 1 / a0;
    _b1 = -2 * cosW0 / a0;
    _b2 = 1 / a0;
    _a1 = -2 * cosW0 / a0;
    _a2 = (1 - alpha) / a0;
  }

  late final double _b0, _b1, _b2, _a1, _a2;
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
