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
    required this.consideredCount,
  });

  final int sensitivityPercent;
  final int bandLowHz;
  final int bandHighHz;

  /// Total impulses captured during calibration.
  final int shotCount;

  /// How many of those were treated as actual shots and fed into the
  /// recommendation (after discarding quiet/odd background noise).
  final int consideredCount;
}

/// Isolates the impulses that most likely correspond to actual shots,
/// discarding ambient noise (talking, wind, distant range activity).
///
/// Two signals separate shots from noise:
///   1. **Loudness** — gunshots saturate the mic far above ambient sound. We
///      sort by peak and split on the largest gap; everything above that
///      natural break is kept. If no pronounced gap exists (all captures are
///      similarly loud) we keep them all.
///   2. **Spectral similarity** — within the loud group, a capture whose
///      dominant frequency sits more than 2× away from the group median is a
///      loud-but-alien event (e.g. a door slam among muzzle cracks) and is
///      dropped. The 2× tolerance is wide enough not to reject normal
///      shot-to-shot variation.
///
/// With fewer than 4 captures there isn't enough data to cluster, so the
/// input is returned unchanged.
List<CalibrationShot> isolateShotCluster(List<CalibrationShot> shots) {
  if (shots.length < 4) return shots;

  final byPeak = [...shots]
    ..sort((a, b) => a.peakAmplitude.compareTo(b.peakAmplitude));
  var splitIdx = 0;
  var maxGap = 0.0;
  for (var i = 1; i < byPeak.length; i++) {
    final gap = byPeak[i].peakAmplitude - byPeak[i - 1].peakAmplitude;
    if (gap > maxGap) {
      maxGap = gap;
      splitIdx = i;
    }
  }
  // Only treat the gap as a noise/shot boundary when it's pronounced (peaks
  // are normalized 0..1, so 0.15 is a clear step). Otherwise keep everything.
  final loud = maxGap >= 0.15 ? byPeak.sublist(splitIdx) : byPeak;
  if (loud.length < 3) return loud;

  final freqs = [for (final s in loud) s.dominantHz]..sort();
  final medianFreq = freqs[freqs.length ~/ 2];
  if (medianFreq <= 0) return loud;
  final similar = [
    for (final s in loud)
      if (s.dominantHz >= medianFreq / 2 && s.dominantHz <= medianFreq * 2) s,
  ];
  return similar.length >= 2 ? similar : loud;
}

/// Computes a [CalibrationSuggestion] from captured impulses.
///
/// First isolates the actual-shot cluster via [isolateShotCluster] so the
/// recommendation ignores background noise (talking, wind). Then:
///
/// Sensitivity: targets the *median* shot in the cluster — threshold = 95%
/// of its peak, converted into the user-facing sensitivity percent. Gunshots
/// are reliably very loud, so a tight 5% margin under the typical shot keeps
/// the detector aggressive at rejecting non-shot noise. Using the median
/// instead of the min keeps one quiet outlier in the cluster from dragging
/// the threshold down.
///
/// Band: spans the union of the 10–90% energy bands across the cluster, padded
/// 20% outward to avoid clipping the actual shot energy of marginal shots.
///
/// Returns null if [shots] is empty.
CalibrationSuggestion? suggestFromShots(List<CalibrationShot> shots) {
  if (shots.isEmpty) return null;
  return suggestFromSelected(
    isolateShotCluster(shots),
    totalCaptured: shots.length,
  );
}

/// Computes a suggestion from an explicit [selected] set of captures —
/// **without** re-clustering. Used when the user has manually overridden which
/// captures count as shots in the auto-configure UI. [totalCaptured] is the
/// full number of captures so the suggestion can report "N of M".
///
/// Returns null if [selected] is empty.
CalibrationSuggestion? suggestFromSelected(
  List<CalibrationShot> selected, {
  required int totalCaptured,
}) {
  if (selected.isEmpty) return null;

  // Sensitivity from the median selected shot, with a tight 5% margin.
  final peaks = [for (final s in selected) s.peakAmplitude]..sort();
  final medianPeak = peaks[peaks.length ~/ 2];
  final threshold = (medianPeak * 0.95).clamp(0.0, 1.0);
  final sensitivity = ((1 - threshold) * 100).round().clamp(0, 100);

  // Band from the widest energy spread across the selected shots.
  var minLow = double.infinity;
  var maxHigh = 0.0;
  for (final s in selected) {
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
    shotCount: totalCaptured,
    consideredCount: selected.length,
  );
}

int _snap(int value, int step) => (value / step).round() * step;
