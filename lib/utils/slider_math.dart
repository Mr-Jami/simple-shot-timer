/// Rounds [raw] to the nearest multiple of [step], clamped to [min, max].
int clampToStep(num raw, {required int min, required int max, required int step}) {
  final snapped = (raw / step).round() * step;
  return snapped.clamp(min, max);
}

/// Double variant of [clampToStep] for fraction-valued sliders.
double clampToStepDouble(
  num raw, {
  required double min,
  required double max,
  required double step,
}) {
  final snapped = (raw / step).round() * step;
  return snapped.clamp(min, max);
}

/// Like [clampToStep], but with a magnetic pull: values landing within
/// [tolerance] of a multiple of [magnet] snap onto that multiple, so drags
/// settle on round values without losing the finer [step] resolution
/// elsewhere. See issue #14.
int softSnap(
  num raw, {
  required int min,
  required int max,
  required int step,
  required int magnet,
  int tolerance = 150,
}) {
  final stepped = clampToStep(raw, min: min, max: max, step: step);
  final nearest = (stepped / magnet).round() * magnet;
  if ((stepped - nearest).abs() <= tolerance) {
    return nearest.clamp(min, max);
  }
  return stepped;
}
