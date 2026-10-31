// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/timer_ports.dart';
import '../services/video/analyzed_clip.dart';
import '../services/video/clip_exporter.dart';
import '../services/video/export_plan.dart';
import '../services/video/hud.dart';
import '../services/video/hud_painter.dart';
import '../services/video/video_work_dir.dart';
import '../utils/cancel_token.dart';
import 'providers.dart';
import 'video_providers.dart';

/// Where the exported video goes once it's made.
enum ExportTarget { photos, share }

/// ENOSPC on Android and iOS: the storage is full.
const _noSpaceErrno = 28;

/// Everything an export needs from the editor.
class ExportJob {
  const ExportJob({
    required this.clip,
    required this.session,
    required this.string,
    required this.plan,
    required this.options,
    required this.labels,
    required this.target,
    this.logo,
  });

  final AnalyzedClip clip;

  /// The clip's work folder: the export is made there and goes with it.
  final VideoSession session;
  final HudString string;
  final ExportPlan plan;
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

/// The video is made and going to Photos: past the point of cancelling.
class ExportSaving extends ExportState {
  const ExportSaving();
}

class ExportDone extends ExportState {
  const ExportDone(this.path, {this.saved = false, this.shareFailed = false});

  final String path;

  /// In the phone's videos (a later Share keeps it so).
  final bool saved;

  /// The share sheet didn't open; Share again may.
  final bool shareFailed;
}

/// The video is made but couldn't go to the phone's videos: not allowed
/// ([denied]), or the save failed. It can still be shared.
class ExportNotSaved extends ExportState {
  const ExportNotSaved(this.path, {required this.denied});

  final String path;
  final bool denied;
}

class ExportFailed extends ExportState {
  const ExportFailed({this.noSpace = false});

  /// The phone's storage ran full.
  final bool noSpace;
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
  late final RunEnvironment _env;
  var _awake = false;
  var _disposed = false;

  @override
  ExportState build(int arg) {
    _env = ref.read(runEnvironmentProvider);
    ref.onDispose(() {
      _disposed = true;
      _cancel.cancel();
      unawaited(_keepAwake(false));
    });
    return const ExportRunning(0);
  }

  Future<void> start(ExportJob job) async {
    // Its own folders: a cancelled export still tidying up can't touch them,
    // and the video can't replace the clip, which may carry the same name
    // (an earlier export picked again).
    final overlayDir = Directory(p.join(job.session.dir.path, 'overlay_$arg'));
    final exportDir = Directory(p.join(job.session.dir.path, 'export_$arg'));
    _clock.start();
    try {
      await _keepAwake(true);
      final colorFix = await _colorFix();
      final overlays = await ref.read(hudFrameRendererProvider)(
        dir: overlayDir,
        plan: job.plan,
        string: job.string,
        options: job.options,
        labels: job.labels,
        logo: job.logo,
        straightAlpha: ref.read(clipExporterProvider).straightAlpha,
        onProgress: (f) => _progress(overlayShare * f),
        cancel: _cancel,
      );
      await exportDir.create(recursive: true);
      final output = p.join(
        exportDir.path,
        ExportPlan.fileName(job.string.date, job.string.string.totalTimeMs),
      );
      await ref.read(clipExporterProvider).export(
            ExportRequest.fromPlan(
              job.plan,
              input: job.session.clipPath,
              output: output,
              overlays: overlays,
              colorFix: colorFix,
            ),
            onProgress: (f) => _progress(overlayShare + (1 - overlayShare) * f),
            cancel: _cancel,
          );
      if (!_cancel.isCancelled) await _deliver(output, job.target);
    } catch (e, stack) {
      // Errors too: the dialog never stays on Exporting for good.
      if (_cancel.isCancelled ||
          (e is ExportException && e.error == ExportError.cancelled)) {
        _emit(const ExportCancelled());
      } else {
        if (e is! Exception) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: e,
            stack: stack,
            library: 'video export',
          ));
        }
        _emit(ExportFailed(
          noSpace: (e is ExportException && e.error == ExportError.noSpace) ||
              (e is FileSystemException &&
                  e.osError?.errorCode == _noSpaceErrno),
        ));
      }
    } finally {
      await _keepAwake(false);
      if (await overlayDir.exists()) await overlayDir.delete(recursive: true);
    }
  }

  /// Saves or shares the exported video again (the result's buttons).
  Future<void> deliver(ExportTarget target) async {
    final path = switch (state) {
      ExportDone(:final path) || ExportNotSaved(:final path) => path,
      _ => null,
    };
    if (path != null) await _deliver(path, target);
  }

  /// Stops the export; what it made so far is deleted.
  void cancel() {
    if (state is! ExportRunning) return;
    _cancel.cancel();
    unawaited(_keepAwake(false));
    _emit(const ExportCancelled());
  }

  /// Saves or shares [path]. A save that fails leaves the video to share.
  Future<void> _deliver(String path, ExportTarget target) async {
    final gallery = ref.read(videoGalleryProvider);
    final saved = switch (state) {
      ExportDone(:final saved) => saved,
      _ => false,
    };
    try {
      switch (target) {
        case ExportTarget.photos:
          _emit(const ExportSaving());
          _emit(await gallery.save(path)
              ? ExportDone(path, saved: true)
              : ExportNotSaved(path, denied: true));
        case ExportTarget.share:
          await gallery.share(path);
          _emit(ExportDone(path, saved: saved));
      }
    } on Exception {
      _emit(target == ExportTarget.photos
          ? ExportNotSaved(path, denied: false)
          : ExportDone(path, saved: saved, shareFailed: true));
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

  /// The screen stays on while this export runs; released once, and at
  /// once on cancel, so a newer export's keep-awake is never undone.
  Future<void> _keepAwake(bool on) async {
    if (_awake == on) return;
    _awake = on;
    await _env.setKeepAwake(on);
  }

  void _progress(double progress) {
    if (_cancel.isCancelled || state is! ExportRunning) return;
    final elapsed = _clock.elapsed;
    // Guessed from the pace so far, once there is enough of it.
    final remaining = progress > 0.05 && elapsed > const Duration(seconds: 2)
        ? elapsed * ((1 - progress) / progress)
        : null;
    _emit(ExportRunning(progress, remaining: remaining));
  }

  /// The dialog may have closed (and this controller with it) while work
  /// was still finishing.
  void _emit(ExportState next) {
    if (!_disposed) state = next;
  }
}

final videoExportProvider = NotifierProvider.autoDispose
    .family<VideoExportController, ExportState, int>(
  VideoExportController.new,
);
