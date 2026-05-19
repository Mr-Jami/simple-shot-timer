import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 Cooley-Tukey FFT.
///
/// Operates on a complex signal stored as two Float64Lists of length [n], a
/// power of two. After the call, [real] and [imag] hold the DFT bins.
///
/// Used by the mic-test screen to estimate the dominant mic frequency so we
/// can verify what the beep actually looks like coming back through the
/// speaker → air → microphone path.
void fftRadix2(Float64List real, Float64List imag) {
  final n = real.length;
  assert(imag.length == n, 'real/imag must have equal length');
  assert((n & (n - 1)) == 0 && n > 1, 'length must be a power of two');

  // Bit-reversal permutation.
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = real[i]; real[i] = real[j]; real[j] = tr;
      final ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
    }
  }

  for (var len = 2; len <= n; len <<= 1) {
    final half = len >> 1;
    final theta = -2 * math.pi / len;
    final wpr = math.cos(theta);
    final wpi = math.sin(theta);
    for (var i = 0; i < n; i += len) {
      var wr = 1.0, wi = 0.0;
      for (var k = 0; k < half; k++) {
        final aRe = real[i + k];
        final aIm = imag[i + k];
        final bRe = real[i + k + half] * wr - imag[i + k + half] * wi;
        final bIm = real[i + k + half] * wi + imag[i + k + half] * wr;
        real[i + k] = aRe + bRe;
        imag[i + k] = aIm + bIm;
        real[i + k + half] = aRe - bRe;
        imag[i + k + half] = aIm - bIm;
        final nextWr = wr * wpr - wi * wpi;
        wi = wr * wpi + wi * wpr;
        wr = nextWr;
      }
    }
  }
}

/// Result of a spectral analysis on a single captured impulse: where the
/// energy actually lives. Returned by [spectralBand]; consumed by the
/// auto-configure flow to suggest a frequency-band filter.
class SpectralBand {
  const SpectralBand({
    required this.lowEdgeHz,
    required this.highEdgeHz,
    required this.dominantHz,
  });
  final double lowEdgeHz;
  final double highEdgeHz;
  final double dominantHz;
}

/// Cumulative-energy band of [samples]. [lowPercentile] / [highPercentile]
/// (defaults 0.10 / 0.90) define the edges: the frequencies below/above which
/// only that fraction of the spectral energy sits. Returns null when the
/// signal is silent.
SpectralBand? spectralBand({
  required Float64List samples,
  required double sampleRate,
  double minHz = 50,
  double maxHz = 12000,
  double lowPercentile = 0.10,
  double highPercentile = 0.90,
}) {
  final n = samples.length;
  assert((n & (n - 1)) == 0 && n > 1, 'samples length must be a power of two');

  final real = Float64List(n);
  final imag = Float64List(n);
  for (var i = 0; i < n; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    real[i] = samples[i] * w;
  }
  fftRadix2(real, imag);

  final binHz = sampleRate / n;
  final minBin = math.max(1, (minHz / binHz).floor());
  final maxBin = math.min(n ~/ 2 - 1, (maxHz / binHz).ceil());
  if (maxBin <= minBin) return null;

  // Power spectrum within [minBin, maxBin]. Linear power, not log — we want
  // the percentiles to reflect actual energy, not perceived loudness.
  final mags = Float64List(maxBin - minBin + 1);
  var total = 0.0;
  var peakMag = 0.0;
  var peakBin = minBin;
  for (var k = minBin; k <= maxBin; k++) {
    final p = real[k] * real[k] + imag[k] * imag[k];
    mags[k - minBin] = p;
    total += p;
    if (p > peakMag) {
      peakMag = p;
      peakBin = k;
    }
  }
  if (total <= 0) return null;

  // Walk the cumulative distribution to locate the percentile edges.
  final lowTarget = total * lowPercentile;
  final highTarget = total * highPercentile;
  var cum = 0.0;
  var lowBin = minBin;
  var highBin = maxBin;
  var lowFound = false;
  for (var k = minBin; k <= maxBin; k++) {
    cum += mags[k - minBin];
    if (!lowFound && cum >= lowTarget) {
      lowBin = k;
      lowFound = true;
    }
    if (cum >= highTarget) {
      highBin = k;
      break;
    }
  }
  return SpectralBand(
    lowEdgeHz: lowBin * binHz,
    highEdgeHz: highBin * binHz,
    dominantHz: peakBin * binHz,
  );
}

/// Finds the strongest non-DC frequency bin in the magnitude spectrum and
/// returns its frequency in Hz, refined by quadratic interpolation of the
/// three bins around the peak (so resolution beats the raw bin spacing).
/// Returns null if the input is silent / has no detectable peak.
double? peakFrequencyHz({
  required Float64List samples,
  required double sampleRate,
  double minHz = 200,
  double maxHz = 8000,
}) {
  final n = samples.length;
  assert((n & (n - 1)) == 0 && n > 1, 'samples length must be a power of two');

  // Hann window — narrows the main lobe enough to resolve adjacent tones
  // without smearing energy across distant bins.
  final real = Float64List(n);
  final imag = Float64List(n);
  for (var i = 0; i < n; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    real[i] = samples[i] * w;
  }
  fftRadix2(real, imag);

  final binHz = sampleRate / n;
  final minBin = math.max(1, (minHz / binHz).floor());
  final maxBin = math.min(n ~/ 2 - 1, (maxHz / binHz).ceil());

  var peakBin = -1;
  var peakMag = 0.0;
  for (var k = minBin; k <= maxBin; k++) {
    final m = real[k] * real[k] + imag[k] * imag[k];
    if (m > peakMag) {
      peakMag = m;
      peakBin = k;
    }
  }
  if (peakBin < 1) return null;

  // Quadratic (parabolic) interpolation around the peak in log-magnitude space.
  final alpha = math.log(math.sqrt(
      real[peakBin - 1] * real[peakBin - 1] +
          imag[peakBin - 1] * imag[peakBin - 1] +
          1e-30));
  final beta = math.log(math.sqrt(peakMag + 1e-30));
  final gamma = math.log(math.sqrt(
      real[peakBin + 1] * real[peakBin + 1] +
          imag[peakBin + 1] * imag[peakBin + 1] +
          1e-30));
  final p = 0.5 * (alpha - gamma) / (alpha - 2 * beta + gamma);
  return (peakBin + p) * binHz;
}
