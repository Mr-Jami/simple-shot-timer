// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_string.dart';
import '../services/video/analyzed_clip.dart';
import '../services/video/clip_audio_source.dart';
import '../services/video/clip_check.dart';
import '../services/video/clip_picker.dart';
import '../services/video/part_window.dart';
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

/// A clip over three minutes: the user picks the part to analyse while its
/// whole sound is scanned for loudness and the filmstrip loads.
class ImportChoosePart extends ImportState {
  const ImportChoosePart({
    required this.info,
    required this.clipPath,
    required this.window,
    this.loudness = const [],
    this.thumbnails = const [],
    this.scanned = false,
  });

  final ClipInfo info;
  final String clipPath;
  final PartWindow window;

  /// The RMS of every [VideoImportController.loudnessBucketMs], filled in
  /// as the scan goes.
  final List<double> loudness;

  /// [VideoImportController.filmstripFrames] JPEGs, null until loaded.
  final List<Uint8List?> thumbnails;

  /// The loudness scan is done (or gave up).
  final bool scanned;

  ImportChoosePart copyWith({
    PartWindow? window,
    List<double>? loudness,
    List<Uint8List?>? thumbnails,
    bool? scanned,
  }) =>
      ImportChoosePart(
        info: info,
        clipPath: clipPath,
        window: window ?? this.window,
        loudness: loudness ?? this.loudness,
        thumbnails: thumbnails ?? this.thumbnails,
        scanned: scanned ?? this.scanned,
      );
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

/// One import: pick a video, check it, let the user choose the part of a
/// long one, decode its sound and analyse it. Owns the clip's work folder
/// until [ImportReady] hands it to the editor; cancelling or leaving the
/// screen before that deletes it.
///
/// One controller per import (the family argument): Riverpod keeps a
/// notifier's fields across a rebuild, so "Choose another" starts a new
/// import rather than invalidating this one with its cancelled token.
class VideoImportController
    extends AutoDisposeFamilyNotifier<ImportState, int> {
  static const showAfter = Duration(milliseconds: 300);
  static const minVisible = Duration(milliseconds: 500);
  static const loudnessBucketMs = 250;
  static const filmstripFrames = 10;

  VideoSession? _session;
  DateTime? _importedAt;
  final _cancel = CancelToken();

  /// Stops the loudness scan and the filmstrip, which only Choose the part
  /// needs.
  final _partJobs = CancelToken();
  var _windowMoved = false;
  Timer? _showTimer;
  Timer? _holdTimer;

  /// Completes once the Analyzing view, if it appeared, has shown long
  /// enough. Timers only, so tests can drive it with a fake clock.
  var _held = Completer<void>();
  var _handedOver = false;

  @override
  ImportState build(int arg) {
    ref.onDispose(() {
      _showTimer?.cancel();
      _holdTimer?.cancel();
      _partJobs.cancel();
      if (!_handedOver) {
        _cancel.cancel();
        unawaited(_session?.dispose());
      }
    });
    return const ImportWorking(ImportStep.picking);
  }

  /// Picks a clip from [source] and analyses it. Reopening [reopen] from a
  /// long clip analyses the part around its markers without asking.
  Future<void> start(ClipSource source, {TimerString? reopen}) async {
    final audio = ref.read(clipAudioSourceProvider);
    await _guard(() async {
      final session =
          _session = await ref.read(videoWorkDirProvider).createSession();
      // Left while the folder was being made: dispose found no session.
      if (_cancel.isCancelled) return session.dispose();
      _importedAt = DateTime.now();
      final path = await ref.read(clipPickerProvider).pick(
        source,
        session,
        onCopyProgress: (f) {
          // A Files pick copies the video before it returns; that wait
          // counts as work, so the Analyzing view can show it.
          _armAnalyzingView();
          _step(ImportStep.reading, progress: f);
        },
        cancel: _cancel,
      );
      if (_cancel.isCancelled) return session.dispose();
      if (path == null) return _finish(const ImportCancelled());
      _armAnalyzingView();

      _step(ImportStep.reading);
      final info = await audio.probe(path);
      if (_cancel.isCancelled) return;
      final problem = checkClip(info);
      if (problem != null) return _finish(ImportProblem(problem));
      if (!needsPart(info.durationMs)) return _analyse(path, info, null);

      final saved = reopen == null ? null : _around(reopen, info.durationMs);
      if (saved != null) return _analyse(path, info, saved);
      _choosePart(path, info);
    });
  }

  /// Moves the Choose-the-part window; the loudness scan no longer places
  /// it once the user has.
  void moveWindow(PartWindow window) {
    _windowMoved = true;
    _updatePart((s) => s.copyWith(window: window));
  }

  /// "Analyze this part": stops the scan and analyses the chosen window,
  /// with the Analyzing view up at once.
  Future<void> analysePart() async {
    final s = state;
    if (s is! ImportChoosePart) return;
    _partJobs.cancel();
    _showTimer?.cancel();
    _holdTimer?.cancel();
    _held = Completer<void>();
    _holdTimer = Timer(minVisible, _held.complete);
    state =
        const ImportWorking(ImportStep.decoding, progress: 0, visible: true);
    await _guard(() => _analyse(s.clipPath, s.info, s.window));
  }

  /// Stops the import and deletes everything it made so far.
  void cancel() {
    if (_handedOver || _cancel.isCancelled) return;
    _cancel.cancel();
    _finish(const ImportCancelled());
  }

  /// The Analyzing view shows once the work after the picker has taken
  /// [showAfter], then stays at least [minVisible].
  void _armAnalyzingView() {
    _showTimer ??= Timer(showAfter, () {
      _holdTimer = Timer(minVisible, _held.complete);
      if (state case ImportWorking(:final step, :final progress)) {
        state = ImportWorking(step, progress: progress, visible: true);
      }
    });
  }

  /// The part of a long clip around a [saved] string's START and last
  /// shot, or null when it has no START.
  static PartWindow? _around(TimerString saved, int durationMs) {
    final start = saved.videoStartMs;
    if (start == null) return null;
    final last = saved.shots.map((s) => s.timeMs).fold(0, math.max);
    return PartWindow.around(start, start + last, durationMs: durationMs);
  }

  void _choosePart(String path, ClipInfo info) {
    _showTimer?.cancel();
    state = ImportChoosePart(
      info: info,
      clipPath: path,
      window: PartWindow.first(info.durationMs),
      thumbnails: List.filled(filmstripFrames, null),
    );
    _loadFilmstrip(path, info.durationMs);
    _scanLoudness(path, info.durationMs);
  }

  /// Changes Choose the part, unless the import has moved on.
  void _updatePart(ImportChoosePart Function(ImportChoosePart) change) {
    if (state case final ImportChoosePart s) state = change(s);
  }

  /// A frame from the middle of each filmstrip cell, as each is ready.
  void _loadFilmstrip(String path, int durationMs) {
    unawaited(ref
        .read(clipAudioSourceProvider)
        .thumbnails(
          path,
          timesMs: [
            for (var i = 0; i < filmstripFrames; i++)
              ((i + 0.5) * durationMs / filmstripFrames).round(),
          ],
          onFrame: (index, jpeg) => _updatePart(
              (s) => s.copyWith(thumbnails: [...s.thumbnails]..[index] = jpeg)),
          cancel: _partJobs,
        )
        .catchError((Object _) {
      // The filmstrip stays empty; the part can still be chosen.
    }));
  }

  /// The whole clip's loudness, batch by batch; once it's all in, the
  /// window moves to the loudest stretch unless the user moved it.
  void _scanLoudness(String path, int durationMs) {
    unawaited(ref
        .read(clipAudioSourceProvider)
        .scanLoudness(
          path,
          bucketMs: loudnessBucketMs,
          onValues: (from, values) => _updatePart((s) =>
              s.copyWith(loudness: [...s.loudness.take(from), ...values])),
          cancel: _partJobs,
        )
        .then<void>((_) {
      _updatePart((s) => s.copyWith(
            scanned: true,
            window: _windowMoved
                ? null
                : PartWindow.loudest(
                    s.loudness,
                    bucketMs: loudnessBucketMs,
                    durationMs: durationMs,
                  ),
          ));
    }).catchError((Object _) {
      // The strip stays partial; the part can still be chosen by eye.
      _updatePart((s) => s.copyWith(scanned: true));
    }));
  }

  Future<void> _analyse(String path, ClipInfo info, PartWindow? part) async {
    final session = _session!;
    final audio = ref.read(clipAudioSourceProvider);
    _step(ImportStep.decoding, progress: 0);
    final decoded = await audio.decode(
      path,
      outputPath: session.pcmPath,
      startMs: part?.startMs ?? 0,
      endMs: part?.endMs,
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
      part: part,
    );
    if (_holdTimer != null) {
      await _held.future;
      if (_cancel.isCancelled) return;
    }
    _showTimer?.cancel();
    _handedOver = true;
    state = ImportReady(clip, session, _importedAt!);
  }

  /// Runs [work], turning its failures into the problem the user sees.
  Future<void> _guard(Future<void> Function() work) async {
    try {
      await work();
    } on ClipAudioException catch (e) {
      if (_cancel.isCancelled) return;
      _finish(ImportProblem(problemFor(e.error)));
    } on Exception {
      if (_cancel.isCancelled) return;
      _finish(const ImportProblem(ClipProblem.failed));
    }
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
    _partJobs.cancel();
    unawaited(_session?.dispose());
    state = end;
  }
}

/// Keyed by an id per import screen (see [VideoImportController]).
final videoImportProvider = NotifierProvider.autoDispose
    .family<VideoImportController, ImportState, int>(
  VideoImportController.new,
);
