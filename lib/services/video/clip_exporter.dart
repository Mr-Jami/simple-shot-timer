// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/cancel_token.dart';
import 'export_plan.dart';

/// A folder of overlay images for the exporter: image `i` (`i.z`,
/// [width] x [height] premultiplied RGBA compressed with zlib) shows from
/// [timesUs]`[i]` (output time) on, its top left at ([x], [y]) in fractions
/// of the frame.
class OverlaySequence {
  const OverlaySequence({
    required this.dir,
    required this.width,
    required this.height,
    required this.timesUs,
    required this.x,
    required this.y,
  });

  final String dir;
  final int width;
  final int height;
  final List<int> timesUs;
  final double x;
  final double y;

  Map<String, Object?> toMap() => {
        'dir': dir,
        'width': width,
        'height': height,
        'timesUs': timesUs,
        'x': x,
        'y': y,
      };
}

/// What to export: [input] from [startMs] to [endMs] into [output], at most
/// [shortSide] pixels on its short side and [maxFps] frames a second, with
/// [overlays] drawn on top.
class ExportRequest {
  const ExportRequest({
    required this.input,
    required this.output,
    required this.startMs,
    required this.endMs,
    required this.overlays,
    required this.shortSide,
    required this.maxFps,
    required this.bitrate,
    required this.colorFix,
  });

  /// [plan] made from [input] into [output].
  ExportRequest.fromPlan(
    ExportPlan plan, {
    required this.input,
    required this.output,
    required this.overlays,
    required this.colorFix,
  })  : startMs = plan.startMs,
        endMs = plan.endMs,
        shortSide = plan.shortSide,
        maxFps = plan.maxFps,
        bitrate = plan.bitrate;

  final String input;
  final String output;
  final int startMs;
  final int endMs;
  final List<OverlaySequence> overlays;

  /// Null keeps the source's size.
  final int? shortSide;

  /// Null keeps the source's frame rate.
  final double? maxFps;
  final int bitrate;

  /// Undo an encoder that converts with BT.601 while tagging BT.709.
  final bool colorFix;
}

/// Why an export failed.
enum ExportError {
  cancelled,
  failed,

  /// The phone's storage ran full.
  noSpace,
  unavailable,
}

class ExportException implements Exception {
  const ExportException(this.error, [this.message]);

  final ExportError error;
  final String? message;

  @override
  String toString() =>
      'ExportException(${error.name}${message == null ? '' : ': $message'})';
}

/// Exports a clip with the overlay. Implemented by the platform in
/// `android/.../ClipExportChannel.kt` and `ios/Runner/ClipExportChannel.swift`.
abstract interface class ClipExporter {
  /// [onProgress] gets 0..1; [cancel] stops it, and it then throws
  /// [ExportError.cancelled] and leaves no file.
  Future<void> export(
    ExportRequest request, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  });

  /// Whether this phone's encoder needs [ExportRequest.colorFix]. Encodes
  /// one frame, so callers keep the answer.
  Future<bool> encoderNeedsColorFix();
}

/// [ClipExporter] over the `cc.jami.simpleshottimer/clip_export` channel.
class ChannelClipExporter implements ClipExporter {
  ChannelClipExporter({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('cc.jami.simpleshottimer/clip_export') {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'progress') return;
      final args = call.arguments as Map<Object?, Object?>;
      _progress[args['jobId']]?.call((args['fraction'] as num).toDouble());
    });
  }

  final MethodChannel _channel;
  final _progress = <int, void Function(double)>{};
  static var _nextJobId = 1;

  @override
  Future<void> export(
    ExportRequest request, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const ExportException(ExportError.cancelled);
    }
    final jobId = _nextJobId++;
    if (onProgress != null) _progress[jobId] = onProgress;
    unawaited(cancel?.whenCancelled.then((_) async {
      try {
        await _channel.invokeMethod<void>('cancel', {'jobId': jobId});
      } on Exception {
        // The export reports its own end.
      }
    }));
    try {
      await _channel.invokeMethod<void>('export', {
        'jobId': jobId,
        'input': request.input,
        'output': request.output,
        'startMs': request.startMs,
        'endMs': request.endMs,
        'shortSide': request.shortSide,
        'maxFps': request.maxFps,
        'bitrate': request.bitrate,
        'colorFix': request.colorFix,
        'overlays': [for (final o in request.overlays) o.toMap()],
      });
    } on PlatformException catch (e) {
      throw _exception(e);
    } on MissingPluginException {
      throw const ExportException(ExportError.unavailable);
    } finally {
      _progress.remove(jobId);
    }
  }

  @override
  Future<bool> encoderNeedsColorFix() async {
    try {
      final m = await _channel
          .invokeMethod<Map<Object?, Object?>>('checkEncoderColors');
      return m?['needsFix'] == true;
    } on PlatformException catch (e) {
      throw _exception(e);
    } on MissingPluginException {
      throw const ExportException(ExportError.unavailable);
    }
  }

  static ExportException _exception(PlatformException e) => ExportException(
        switch (e.code) {
          'cancelled' => ExportError.cancelled,
          'no_space' => ExportError.noSpace,
          _ => ExportError.failed,
        },
        e.message,
      );
}
