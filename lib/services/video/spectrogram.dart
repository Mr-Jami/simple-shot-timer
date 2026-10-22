// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import '../../utils/fft.dart';

/// The spectrogram the clip analyzer reads: 256-point Hann-windowed FFT,
/// 128-sample hop, 128 bins per frame.
///
/// Each bin is one byte on the scale of the video shot timer reference
/// (`video-shot-timer/src/shot-detector.mjs`), 256 + 45·log10(magnitude): about
/// 1 is the silence floor, 255 is close to full scale, and one unit is about
/// 0.44 dB. The shot test's thresholds are tuned on that scale, so it is kept
/// exactly, with one fix (see [byteFor]).
///
/// Pure Dart and plain data, so it can be built and returned by an isolate.
class Spectrogram {
  Spectrogram._(this.values, this.frameCount, this.sampleRate, this.sampleCount);

  static const int fftSize = 256;
  static const int hop = 128;
  static const int bins = fftSize ~/ 2;

  /// [frameCount] × [bins] values, frame-major.
  final Uint8List values;
  final int frameCount;
  final int sampleRate;
  final int sampleCount;

  double get durationSeconds => sampleCount / sampleRate;

  /// Frames per second the way the reference counts them (frames over the
  /// clip's duration), about 375 at 48 kHz. Every time window in the analyzer
  /// is converted to frames with this rate.
  double get framesPerSecond => frameCount / durationSeconds;

  double get binHz => sampleRate / fftSize;

  int value(int frame, int bin) => values[frame * bins + bin];

  double secondsAt(int frame) => frame / framesPerSecond;

  /// Builds the spectrogram of mono 16-bit [samples].
  factory Spectrogram.compute(Int16List samples, int sampleRate) {
    final n = samples.length;
    // Same frame count as the reference loop (`off + fftSize < length`).
    final frameCount = n > fftSize ? (n - fftSize - 1) ~/ hop + 1 : 0;
    final values = Uint8List(frameCount * bins);
    final window = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (fftSize - 1))) / 32768;
    }
    final real = Float64List(fftSize);
    final imag = Float64List(fftSize);
    for (var frame = 0; frame < frameCount; frame++) {
      final offset = frame * hop;
      for (var i = 0; i < fftSize; i++) {
        real[i] = samples[offset + i] * window[i];
      }
      imag.fillRange(0, fftSize, 0);
      fftRadix2(real, imag);
      final row = frame * bins;
      for (var k = 0; k < bins; k++) {
        final magnitude =
            (2 / fftSize) * math.sqrt(real[k] * real[k] + imag[k] * imag[k]);
        values[row + k] = byteFor(magnitude);
      }
    }
    return Spectrogram._(values, frameCount, sampleRate, n);
  }

  /// The reference stores `max(-255, 45·log10(m))` in a Uint8Array, so values
  /// below full scale wrap to 256 + that. The one change: above a magnitude of
  /// about 0.95 (only extreme low-frequency energy) the reference wraps to 0,
  /// which reads as silence; here it clamps to 255.
  static int byteFor(double magnitude) {
    if (!(magnitude > 0)) return 1;
    var v = math.max(-255.0, math.log(magnitude) / math.ln10 * 45);
    // log(x)/ln10 lands a hair off where JavaScript's Math.log10 is exact
    // (log10(0.1) is -0.9999999999999998 here), and truncation would then drop
    // a whole unit. Snap values within rounding error of an integer.
    final nearest = v.roundToDouble();
    if ((v - nearest).abs() < 1e-9) v = nearest;
    if (v > -1) return 255;
    return v.truncate() & 0xFF;
  }
}
