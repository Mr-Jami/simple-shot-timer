/// A single impulse captured during the auto-configure calibration run.
///
/// Carries enough information to suggest both a sensitivity threshold (from
/// [peakAmplitude]) and a frequency band (from [lowEdgeHz]/[highEdgeHz]) once
/// several shots have been collected.
class CalibrationShot {
  const CalibrationShot({
    required this.peakAmplitude,
    required this.lowEdgeHz,
    required this.highEdgeHz,
    required this.dominantHz,
  });

  /// Normalized peak in [0, 1] — same units as [AppSettings.detectionThreshold].
  final double peakAmplitude;

  /// Frequency below which only 10% of the shot's spectral energy sits.
  final double lowEdgeHz;

  /// Frequency below which 90% of the shot's spectral energy sits.
  final double highEdgeHz;

  /// Bin with the largest single-frequency contribution.
  final double dominantHz;
}
