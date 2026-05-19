import 'dart:math' as math;

import '../models/app_settings.dart';
import '../models/calibration_shot.dart';

/// Settings the auto-configure flow proposes after listening to a series of
/// shots. The UI shows these alongside the user's current values so they can
/// accept or discard the suggestion.
class CalibrationSuggestion {
  const CalibrationSuggestion({
    required this.sensitivityPercent,
    required this.bandLowHz,
    required this.bandHighHz,
    required this.shotCount,
  });

  final int sensitivityPercent;
  final int bandLowHz;
  final int bandHighHz;
  final int shotCount;
}

/// Computes a [CalibrationSuggestion] from captured impulses.
///
/// Sensitivity: targets the *quietest* shot — threshold = 75% of its peak,
/// converted back into the user-facing sensitivity percent. This lets every
/// captured shot cross the threshold with a 25% safety margin.
///
/// Band: spans the union of the 10–90% energy bands across all shots, padded
/// 20% outward to avoid clipping the actual shot energy of marginal shots.
///
/// Returns null if [shots] is empty.
CalibrationSuggestion? suggestFromShots(List<CalibrationShot> shots) {
  if (shots.isEmpty) return null;

  // Sensitivity from the quietest captured shot.
  var minPeak = double.infinity;
  for (final s in shots) {
    if (s.peakAmplitude < minPeak) minPeak = s.peakAmplitude;
  }
  final threshold = (minPeak * 0.75).clamp(0.0, 1.0);
  final sensitivity = ((1 - threshold) * 100).round().clamp(0, 100);

  // Band from the widest energy spread observed across shots.
  var minLow = double.infinity;
  var maxHigh = 0.0;
  for (final s in shots) {
    if (s.lowEdgeHz < minLow) minLow = s.lowEdgeHz;
    if (s.highEdgeHz > maxHigh) maxHigh = s.highEdgeHz;
  }
  final paddedLow = (minLow * 0.8).round();
  final paddedHigh = (maxHigh * 1.2).round();

  // Snap to slider steps so the values exactly match what the slider will
  // display once written into settings.
  final bandLowHz = _snap(paddedLow, 50)
      .clamp(AppSettings.bandLowMinHz, AppSettings.bandLowMaxHz);
  final bandHighHzRaw = _snap(paddedHigh, 100)
      .clamp(AppSettings.bandHighMinHz, AppSettings.bandHighMaxHz);
  // Enforce the same 500 Hz minimum separation the settings UI uses, so
  // applying the suggestion never produces an invalid (collapsed) band.
  final bandHighHz =
      math.max(bandHighHzRaw, bandLowHz + 500).clamp(
            AppSettings.bandHighMinHz,
            AppSettings.bandHighMaxHz,
          );

  return CalibrationSuggestion(
    sensitivityPercent: sensitivity,
    bandLowHz: bandLowHz,
    bandHighHz: bandHighHz,
    shotCount: shots.length,
  );
}

int _snap(int value, int step) => (value / step).round() * step;
