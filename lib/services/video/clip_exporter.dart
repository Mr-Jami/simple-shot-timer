// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/cancel_token.dart';

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
    this.shortSide,
    this.maxFps,
    this.bitrate = 12000000,
    this.colorFix = false,
  });

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

class ExportedClip {
  const ExportedClip({
    required this.path,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    this.firstOverlayUs,
  });

  final String path;
  final int fileSizeBytes;
  final int width;
  final int height;

  /// The first frame time the overlay saw: 0 when Media3 counts from the
  /// trimmed start.
  final int? firstOverlayUs;
}

/// Why an export failed.
enum ExportError { cancelled, failed, unavailable }

class ExportException implements Exception {
  const ExportException(this.error, [this.message]);

  final ExportError error;
  final String? message;

  @override
  String toString() =>
      'ExportException(${error.name}${message == null ? '' : ': $message'})';
}

/// Exports a clip with the overlay. Implemented by the platform in
/// `android/.../ClipExportChannel.kt`.
abstract interface class ClipExporter {
  /// [onProgress] gets 0..1; [cancel] stops it, and it then throws
  /// [ExportError.cancelled] and leaves no file.
  Future<ExportedClip> export(
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
  Future<ExportedClip> export(
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
      final m = await _invoke('export', {
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
      return ExportedClip(
        path: request.output,
        fileSizeBytes: m['fileSizeBytes'] as int? ?? 0,
        width: m['width'] as int? ?? 0,
        height: m['height'] as int? ?? 0,
        firstOverlayUs: m['firstOverlayUs'] as int?,
      );
    } finally {
      _progress.remove(jobId);
    }
  }

  @override
  Future<bool> encoderNeedsColorFix() async {
    final m = await _invoke('checkEncoderColors', const {});
    return m['matrix'] == 'bt601';
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>(method, arguments);
      if (result == null) {
        throw const ExportException(ExportError.failed, 'no result');
      }
      return result;
    } on PlatformException catch (e) {
      throw ExportException(
        e.code == 'cancelled' ? ExportError.cancelled : ExportError.failed,
        e.message,
      );
    } on MissingPluginException {
      throw const ExportException(ExportError.unavailable);
    }
  }
}
