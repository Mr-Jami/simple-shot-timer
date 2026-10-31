// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:isolate';

import 'clip_analyzer.dart';

/// Runs the clip analyzer off the UI thread. A port so the import flow and
/// the editor can be tested with canned results.
abstract interface class ClipAnalyzerRunner {
  /// Analyses the decoder's PCM file at [pcmPath].
  Future<ClipAnalysis> analyze(String pcmPath, int sampleRate);

  /// The same analysis at another sensitivity (reuses the spectrogram).
  Future<ClipAnalysis> resense(
      ClipAnalysis analysis, ShotSensitivity sensitivity);
}

class IsolateClipAnalyzer implements ClipAnalyzerRunner {
  const IsolateClipAnalyzer();

  @override
  Future<ClipAnalysis> analyze(String pcmPath, int sampleRate) =>
      analyzePcmFile(pcmPath, sampleRate);

  @override
  Future<ClipAnalysis> resense(
    ClipAnalysis analysis,
    ShotSensitivity sensitivity,
  ) =>
      Isolate.run(() => analysis.withSensitivity(sensitivity));
}
