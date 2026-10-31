// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

/// The video editor's timeline zooms between these, in logical pixels per
/// second: from a whole string in view to single milliseconds.
const double minPxPerSecond = 50;
const double maxPxPerSecond = 2000;

double clampZoom(double pxPerSecond) =>
    pxPerSecond.clamp(minPxPerSecond, maxPxPerSecond).toDouble();

/// The playhead after zooming from [oldPxPerSecond] to [newPxPerSecond]
/// with the fingers [focalPx] from the playhead: the moment under the
/// fingers stays under them.
double zoomAround({
  required double playheadMs,
  required double focalPx,
  required double oldPxPerSecond,
  required double newPxPerSecond,
}) {
  final focalMs = playheadMs + focalPx / oldPxPerSecond * 1000;
  return focalMs - focalPx / newPxPerSecond * 1000;
}

/// How far content follows a finger dragged [overscroll] past an end of a
/// timeline [extent] wide: less and less, never a hard stop (iOS's rubber
/// band, used on both platforms).
double rubberBand(double overscroll, double extent, {double constant = 0.55}) {
  if (extent <= 0) return 0;
  final sign = overscroll < 0 ? -1 : 1;
  final x = overscroll.abs();
  return sign * (x * extent * constant) / (extent + constant * x);
}

/// Whether moving the playhead from [fromMs] to [toMs] passed a marker
/// (landing on one counts; leaving one doesn't).
bool crossesMarker(double fromMs, double toMs, Iterable<int> markers) {
  if (fromMs == toMs) return false;
  final forward = toMs > fromMs;
  for (final m in markers) {
    if (forward ? (m > fromMs && m <= toMs) : (m < fromMs && m >= toMs)) {
      return true;
    }
  }
  return false;
}
