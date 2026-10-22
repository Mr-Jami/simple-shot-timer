// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/video/analyzed_clip.dart';
import '../services/video/clip_audio_source.dart';
import '../services/video/clip_check.dart';
import '../services/video/clip_picker.dart';
import '../services/video/video_work_dir.dart';
import '../utils/cancel_token.dart';
import 'video_providers.dart';

/// The steps of the Analyzing view.
enum ImportStep { picking, reading, decoding, analyzing }

sealed class ImportState {
  const ImportState();
}

class ImportWorking extends ImportState {
  const ImportWorking(this.step, {this.progress, this.visible = false});

  final ImportStep step;

  /// 0..1 when the step reports it.
  final double? progress;

  /// Whether the Analyzing view shows. It appears only when the work after
  /// the picker takes more than 300 ms, then stays at least 500 ms.
  final bool visible;
}

class ImportProblem extends ImportState {
  const ImportProblem(this.problem);

  final ClipProblem problem;
}

/// The user backed out of the picker or pressed Cancel.
class ImportCancelled extends ImportState {
  const ImportCancelled();
}

class ImportReady extends ImportState {
  const ImportReady(this.clip, this.session, this.importedAt);

  final AnalyzedClip clip;

  /// Handed over to the editor, which deletes it when it closes.
  final VideoSession session;
  final DateTime importedAt;
}

/// One import: pick a video, check it, decode its sound and analyse it.
/// Owns the clip's work folder until [ImportReady] hands it to the editor;
/// cancelling or leaving the screen before that deletes it.
class VideoImportController extends AutoDisposeNotifier<ImportState> {
  static const showAfter = Duration(milliseconds: 300);
  static const minVisible = Duration(milliseconds: 500);

  VideoSession? _session;
  final _cancel = CancelToken();
  Timer? _showTimer;
  Timer? _holdTimer;

  /// Completes once the Analyzing view, if it appeared, has shown long
  /// enough. Timers only, so tests can drive it with a fake clock.
  final _held = Completer<void>();
  var _handedOver = false;

  @override
  ImportState build() {
    ref.onDispose(() {
      _showTimer?.cancel();
      _holdTimer?.cancel();
      if (!_handedOver) {
        _cancel.cancel();
        unawaited(_session?.dispose());
      }
    });
    return const ImportWorking(ImportStep.picking);
  }

  Future<void> start(ClipSource source) async {
    final audio = ref.read(clipAudioSourceProvider);
    try {
      final session =
          _session = await ref.read(videoWorkDirProvider).createSession();
      final importedAt = DateTime.now();
      final path = await ref.read(clipPickerProvider).pick(
            source,
            session,
            onCopyProgress: (f) => _step(ImportStep.reading, progress: f),
          );
      if (_cancel.isCancelled) return;
      if (path == null) return _finish(const ImportCancelled());
      _showTimer = Timer(showAfter, () {
        _holdTimer = Timer(minVisible, _held.complete);
        if (state case ImportWorking(:final step, :final progress)) {
          state = ImportWorking(step, progress: progress, visible: true);
        }
      });

      _step(ImportStep.reading);
      final info = await audio.probe(path);
      if (_cancel.isCancelled) return;
      final problem = checkClip(info);
      if (problem != null) return _finish(ImportProblem(problem));

      _step(ImportStep.decoding, progress: 0);
      final decoded = await audio.decode(
        path,
        outputPath: session.pcmPath,
        onProgress: (f) => _step(ImportStep.decoding, progress: f),
        cancel: _cancel,
      );
      _step(ImportStep.analyzing);
      final analysis = await ref
          .read(clipAnalyzerProvider)
          .analyze(session.pcmPath, decoded.sampleRate);
      await session.deletePcm();
      if (_cancel.isCancelled) return;

      final clip = AnalyzedClip(
        info: info,
        analysis: analysis,
        audioOriginMs: (decoded.firstSampleTimeUs / 1000).round(),
      );
      if (_holdTimer != null) {
        await _held.future;
        if (_cancel.isCancelled) return;
      }
      _showTimer?.cancel();
      _handedOver = true;
      state = ImportReady(clip, session, importedAt);
    } on ClipAudioException catch (e) {
      if (_cancel.isCancelled) return;
      _finish(ImportProblem(problemFor(e.error)));
    } on Exception {
      if (_cancel.isCancelled) return;
      _finish(const ImportProblem(ClipProblem.failed));
    }
  }

  /// Stops the import and deletes everything it made so far.
  void cancel() {
    if (_handedOver || _cancel.isCancelled) return;
    _cancel.cancel();
    _finish(const ImportCancelled());
  }

  void _step(ImportStep step, {double? progress}) {
    if (_cancel.isCancelled || _handedOver) return;
    final visible = switch (state) {
      ImportWorking(:final visible) => visible,
      _ => false,
    };
    state = ImportWorking(step, progress: progress, visible: visible);
  }

  void _finish(ImportState end) {
    _showTimer?.cancel();
    _holdTimer?.cancel();
    unawaited(_session?.dispose());
    state = end;
  }
}

final videoImportProvider =
    NotifierProvider.autoDispose<VideoImportController, ImportState>(
  VideoImportController.new,
);
