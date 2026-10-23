// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/video/analyzed_clip.dart';
import '../services/video/clip_exporter.dart';
import '../services/video/export_plan.dart';
import '../services/video/hud.dart';
import '../services/video/video_work_dir.dart';
import '../utils/cancel_token.dart';
import '../widgets/video/hud_painter.dart';
import 'providers.dart';
import 'video_providers.dart';

/// Where the exported video goes once it's made.
enum ExportTarget { photos, share }

/// Everything an export needs from the editor.
class ExportJob {
  const ExportJob({
    required this.clip,
    required this.session,
    required this.string,
    required this.options,
    required this.labels,
    required this.target,
    this.logo,
  });

  final AnalyzedClip clip;

  /// The clip's work folder: the export is made there and goes with it.
  final VideoSession session;
  final HudString string;
  final HudOptions options;
  final HudLabels labels;
  final ExportTarget target;
  final ui.Image? logo;
}

sealed class ExportState {
  const ExportState();
}

class ExportRunning extends ExportState {
  const ExportRunning(this.progress, {this.remaining});

  /// 0..1 over the overlay and the video.
  final double progress;

  /// Known once enough has been done to tell.
  final Duration? remaining;
}

class ExportDone extends ExportState {
  const ExportDone(this.path, {required this.target, this.saved = false});

  final String path;
  final ExportTarget target;

  /// In the phone's videos.
  final bool saved;
}

/// The phone wouldn't let the video be saved; the file is still there to
/// share.
class ExportNoAccess extends ExportState {
  const ExportNoAccess(this.path);

  final String path;
}

class ExportFailed extends ExportState {
  const ExportFailed();
}

class ExportCancelled extends ExportState {
  const ExportCancelled();
}

/// One export: the overlay images, then the video, then Save or Share.
/// Keeps the screen on meanwhile. One controller per export (the family
/// argument), like the import.
class VideoExportController
    extends AutoDisposeFamilyNotifier<ExportState, int> {
  /// The overlay's share of the progress; the video takes the rest.
  static const overlayShare = 0.2;

  final _cancel = CancelToken();
  final _clock = Stopwatch();

  @override
  ExportState build(int arg) {
    ref.onDispose(_cancel.cancel);
    return const ExportRunning(0);
  }

  Future<void> start(ExportJob job) async {
    final env = ref.read(runEnvironmentProvider);
    final overlayDir = Directory(p.join(job.session.dir.path, 'overlay'));
    _clock.start();
    await env.setKeepAwake(true);
    try {
      final colorFix = await _colorFix();
      final plan = ExportPlan(
        job.string,
        job.clip.info,
        fromMs: job.clip.fromMs,
        toMs: job.clip.toMs,
      );
      if (await overlayDir.exists()) await overlayDir.delete(recursive: true);
      final overlays = await ref.read(hudFrameRendererProvider)(
        dir: overlayDir,
        plan: plan,
        string: job.string,
        options: job.options,
        labels: job.labels,
        logo: job.logo,
        onProgress: (f) => _progress(overlayShare * f),
        cancel: _cancel,
      );
      final output = p.join(
        job.session.dir.path,
        ExportPlan.fileName(job.string.date, job.string.string.totalTimeMs),
      );
      await ref.read(clipExporterProvider).export(
            ExportRequest(
              input: job.session.clipPath,
              output: output,
              startMs: plan.startMs,
              endMs: plan.endMs,
              overlays: overlays,
              shortSide: plan.shortSide,
              maxFps: plan.maxFps,
              bitrate: plan.bitrate,
              colorFix: colorFix,
            ),
            onProgress: (f) => _progress(overlayShare + (1 - overlayShare) * f),
            cancel: _cancel,
          );
      if (_cancel.isCancelled) return;
      state = ExportDone(output, target: job.target);
      await _deliver(output, job.target);
    } on ExportException catch (e) {
      if (_cancel.isCancelled || e.error == ExportError.cancelled) {
        state = const ExportCancelled();
      } else {
        state = const ExportFailed();
      }
    } on Exception {
      state =
          _cancel.isCancelled ? const ExportCancelled() : const ExportFailed();
    } finally {
      await env.setKeepAwake(false);
      if (await overlayDir.exists()) await overlayDir.delete(recursive: true);
    }
  }

  /// Saves or shares the exported video again (the Done view's buttons).
  Future<void> deliver(ExportTarget target) async {
    final path = switch (state) {
      ExportDone(:final path) || ExportNoAccess(:final path) => path,
      _ => null,
    };
    if (path != null) await _deliver(path, target);
  }

  /// Stops the export; what it made so far is deleted.
  void cancel() {
    if (state is! ExportRunning) return;
    _cancel.cancel();
    state = const ExportCancelled();
  }

  Future<void> _deliver(String path, ExportTarget target) async {
    final gallery = ref.read(videoGalleryProvider);
    switch (target) {
      case ExportTarget.photos:
        final saved = await gallery.save(path);
        state = saved
            ? ExportDone(path, target: target, saved: true)
            : ExportNoAccess(path);
      case ExportTarget.share:
        await gallery.share(path);
    }
  }

  /// Whether to correct the encoder's colours: asked once, then kept.
  Future<bool> _colorFix() async {
    final settings = ref.read(settingsServiceProvider);
    final known = settings.encoderColorFix;
    if (known != null) return known;
    try {
      final fix = await ref.read(clipExporterProvider).encoderNeedsColorFix();
      await settings.setEncoderColorFix(fix);
      return fix;
    } on ExportException {
      // No answer: export as the encoder makes it.
      return false;
    }
  }

  void _progress(double progress) {
    if (_cancel.isCancelled || state is! ExportRunning) return;
    final elapsed = _clock.elapsed;
    // Guessed from the pace so far, once there is enough of it.
    final remaining = progress > 0.05 && elapsed > const Duration(seconds: 2)
        ? elapsed * ((1 - progress) / progress)
        : null;
    state = ExportRunning(progress, remaining: remaining);
  }
}

final videoExportProvider = NotifierProvider.autoDispose
    .family<VideoExportController, ExportState, int>(
  VideoExportController.new,
);
