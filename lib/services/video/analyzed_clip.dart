// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import '../../models/timer_string.dart';
import 'clip_analyzer.dart';
import 'clip_audio_source.dart';
import 'clip_signal.dart';
import 'marker_doc.dart';
import 'part_window.dart';
import 'start_finder.dart';

/// A clip and what the analyzer found in it, in clip milliseconds: the one
/// place where analyzer seconds (from the first decoded sample) become clip
/// time.
class AnalyzedClip {
  const AnalyzedClip({
    required this.info,
    required this.analysis,
    required this.audioOriginMs,
    this.part,
  });

  final ClipInfo info;
  final ClipAnalysis analysis;

  /// Clip time of the first decoded audio sample.
  final int audioOriginMs;

  /// The part of a long clip that was analysed; null for the whole clip.
  final PartWindow? part;

  /// The stretch the editor shows and markers stay in.
  int get fromMs => part?.startMs ?? 0;
  int get toMs => part?.endMs ?? info.durationMs;

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

  /// Whether this looks like the clip [saved] was made from: the same
  /// length (±1 s), recording date (±2 s) and beep (±100 ms), each checked
  /// when both sides know it. A messenger re-encode can fail it, so the
  /// caller asks rather than refuses.
  bool matches(TimerString saved) {
    final duration = saved.videoDurationMs;
    if (duration != null && (duration - info.durationMs).abs() > 1000) {
      return false;
    }
    final recorded = saved.videoRecordedAt;
    final created = info.creationTime;
    if (recorded != null &&
        created != null &&
        recorded.difference(created).abs() > const Duration(seconds: 2)) {
      return false;
    }
    final savedStart = saved.videoStartMs;
    final start = startMs;
    if (savedStart != null &&
        start != null &&
        (savedStart - start).abs() > 100) {
      return false;
    }
    return true;
  }

  /// Where a shot dropped at [ms] really starts: the sharpest onset within
  /// [radiusMs], in clip time, or null when nothing there rises like a shot.
  int? snapToOnset(int ms, {int radiusMs = 8}) {
    final s = analysis.spectrogram;
    final fps = s.framesPerSecond;
    if (fps <= 0) return null;
    final frame = ((ms - audioOriginMs) / 1000 * fps).round();
    final onset =
        strongestOnset(s, frame, radiusFrames: (radiusMs / 1000 * fps).ceil());
    return onset == null ? null : toClipMs(s.secondsAt(onset));
  }

  MarkerDoc toDoc() => MarkerDoc.detected(
        fromMs: fromMs,
        toMs: toMs,
        startMs: startMs,
        shotMs: shotMs,
      );

  /// The same clip and part with [analysis] (another sensitivity).
  AnalyzedClip withAnalysis(ClipAnalysis analysis) => AnalyzedClip(
        info: info,
        analysis: analysis,
        audioOriginMs: audioOriginMs,
        part: part,
      );
}
