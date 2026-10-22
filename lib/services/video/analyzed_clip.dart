// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'clip_analyzer.dart';
import 'clip_audio_source.dart';
import 'marker_doc.dart';
import 'start_finder.dart';

/// A clip and what the analyzer found in it, in clip milliseconds: the one
/// place where analyzer seconds (from the first decoded sample) become clip
/// time.
class AnalyzedClip {
  const AnalyzedClip({
    required this.info,
    required this.analysis,
    required this.audioOriginMs,
  });

  final ClipInfo info;
  final ClipAnalysis analysis;

  /// Clip time of the first decoded audio sample.
  final int audioOriginMs;

  int toClipMs(double seconds) => audioOriginMs + (seconds * 1000).round();

  /// START in clip time, or null when no beep was convincing.
  int? get startMs => switch (analysis.startSeconds) {
        final double s => toClipMs(s),
        null => null,
      };

  /// Every detected shot the user may want, in clip time: all of them except
  /// the start beep's own attack and stop click, so moving START earlier or
  /// later reveals or hides real shots only.
  List<int> get shotMs {
    final beep = analysis.start;
    return [
      for (final s in analysis.shotSeconds)
        if (beep == null ||
            !((s > beep.onsetSeconds - 0.03 &&
                    s <= beep.onsetSeconds + minDrawSeconds) ||
                isStopClick(beep, s)))
          toClipMs(s),
    ];
  }

  MarkerDoc toDoc() => MarkerDoc.detected(
        durationMs: info.durationMs,
        startMs: startMs,
        shotMs: shotMs,
      );

  AnalyzedClip withSensitivity(ShotSensitivity sensitivity) => AnalyzedClip(
        info: info,
        analysis: analysis.withSensitivity(sensitivity),
        audioOriginMs: audioOriginMs,
      );
}
