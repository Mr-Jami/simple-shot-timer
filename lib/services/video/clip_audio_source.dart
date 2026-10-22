// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/cancel_token.dart';

/// Why a clip's sound could not be read.
enum ClipAudioError {
  /// The file has no audio track (a screen recording, some time-lapses), or
  /// one that decodes to nothing.
  noAudioTrack,

  /// The phone has no decoder for the clip's sound (e.g. Dolby Digital on
  /// some Android phones).
  unsupportedCodec,

  /// The file is missing, unreadable or not a video.
  unreadableFile,

  /// The platform decoder failed part-way.
  decodeFailed,

  /// No decoder on this platform yet (iOS until its pass).
  unavailable,

  /// The caller cancelled the decode.
  cancelled,
}

/// Thrown when a clip's sound cannot be read; [error] says why.
class ClipAudioException implements Exception {
  const ClipAudioException(this.error, [this.message]);

  final ClipAudioError error;
  final String? message;

  @override
  String toString() =>
      'ClipAudioException(${error.name}${message == null ? '' : ': $message'})';
}

/// What the platform knows about a clip before decoding it. The analyzer
/// needs only the audio fields; the rest is for the editor and the export
/// (orientation, HDR, stepping by frame, the history entry's date).
class ClipInfo {
  const ClipInfo({
    required this.hasAudio,
    required this.durationMs,
    this.audioMime,
    this.videoMime,
    this.rotationDegrees = 0,
    this.width,
    this.height,
    this.colorTransfer,
    this.frameRate,
    this.captureFrameRate,
    this.creationTime,
  });

  final bool hasAudio;
  final int durationMs;
  final String? audioMime;
  final String? videoMime;
  final int rotationDegrees;

  /// The picture's size as displayed (rotation applied), to size the video
  /// box before the first frame decodes.
  final int? width;
  final int? height;

  /// 'sdr', 'pq' (HDR10, Dolby Vision) or 'hlg'; null when unknown.
  final String? colorTransfer;
  final double? frameRate;

  /// The rate the camera recorded at, when it differs in kind from
  /// [frameRate]: slow motion records faster, time-lapse slower.
  final double? captureFrameRate;

  /// When the clip was recorded, if the file says.
  final DateTime? creationTime;

  bool get isHdr => colorTransfer == 'pq' || colorTransfer == 'hlg';
}

/// The decoded sound of a clip: raw little-endian 16-bit mono PCM (the first
/// channel) at [pcmPath], which the caller deletes.
class DecodedAudio {
  const DecodedAudio({
    required this.pcmPath,
    required this.sampleRate,
    required this.channelCount,
    required this.sampleCount,
    required this.firstSampleTimeUs,
  });

  final String pcmPath;
  final int sampleRate;

  /// Channels in the source track; the file holds only the first.
  final int channelCount;
  final int sampleCount;

  /// Media time of the first PCM sample, to place the sound against the
  /// picture.
  final int firstSampleTimeUs;

  double get durationSeconds => sampleCount / sampleRate;
}

/// Reads a clip's sound for the analyzer. Implemented by the platform in
/// `android/.../ClipAudioChannel.kt`; iOS follows the same contract later.
abstract interface class ClipAudioSource {
  /// Reads [path]'s container metadata without decoding anything.
  Future<ClipInfo> probe(String path);

  /// Decodes [path]'s audio track to [outputPath]. Of several tracks it takes
  /// the mono or stereo AAC one (iPhone spatial-audio clips add a
  /// four-channel track), else the first. [onProgress] gets 0..1 while it
  /// runs; [cancel] stops it, and it then throws
  /// [ClipAudioError.cancelled] and leaves no file.
  Future<DecodedAudio> decode(
    String path, {
    required String outputPath,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  });
}

/// [ClipAudioSource] over the `cc.jami.simpleshottimer/clip_audio` channel
/// (Android: `ClipAudioChannel.kt`).
class ChannelClipAudioSource implements ClipAudioSource {
  ChannelClipAudioSource({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('cc.jami.simpleshottimer/clip_audio') {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  final MethodChannel _channel;
  final _progress = <int, void Function(double)>{};
  static var _nextJobId = 1;

  Future<void> _onPlatformCall(MethodCall call) async {
    if (call.method != 'progress') return;
    final args = call.arguments as Map<Object?, Object?>;
    final fraction = (args['fraction'] as num).toDouble();
    _progress[args['jobId'] as int]?.call(fraction);
  }

  @override
  Future<ClipInfo> probe(String path) async {
    final m = await _invoke('probe', {'path': path});
    final created = m['creationTimeMs'] as int?;
    return ClipInfo(
      hasAudio: m['hasAudio'] as bool? ?? false,
      durationMs: m['durationMs'] as int? ?? 0,
      audioMime: m['audioMime'] as String?,
      videoMime: m['videoMime'] as String?,
      rotationDegrees: m['rotation'] as int? ?? 0,
      width: m['width'] as int?,
      height: m['height'] as int?,
      colorTransfer: m['colorTransfer'] as String?,
      frameRate: (m['frameRate'] as num?)?.toDouble(),
      captureFrameRate: (m['captureFrameRate'] as num?)?.toDouble(),
      creationTime: created == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
    );
  }

  @override
  Future<DecodedAudio> decode(
    String path, {
    required String outputPath,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const ClipAudioException(ClipAudioError.cancelled);
    }
    final jobId = _nextJobId++;
    if (onProgress != null) _progress[jobId] = onProgress;
    unawaited(cancel?.whenCancelled.then((_) async {
      try {
        await _channel.invokeMethod<void>('cancel', {'jobId': jobId});
      } on Exception {
        // The decode reports its own end.
      }
    }));
    final Map<Object?, Object?> m;
    try {
      m = await _invoke('decode', {
        'path': path,
        'outputPath': outputPath,
        'jobId': jobId,
      });
    } finally {
      _progress.remove(jobId);
    }
    return DecodedAudio(
      pcmPath: outputPath,
      sampleRate: m['sampleRate'] as int,
      channelCount: m['channelCount'] as int,
      sampleCount: m['sampleCount'] as int,
      firstSampleTimeUs: m['firstSampleTimeUs'] as int? ?? 0,
    );
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result =
          await _channel.invokeMethod<Map<Object?, Object?>>(method, arguments);
      if (result == null) {
        throw ClipAudioException(ClipAudioError.decodeFailed, 'no result');
      }
      return result;
    } on PlatformException catch (e) {
      throw ClipAudioException(
          _errors[e.code] ?? ClipAudioError.decodeFailed, e.message);
    } on MissingPluginException {
      throw const ClipAudioException(ClipAudioError.unavailable);
    }
  }

  static const _errors = {
    'no_audio_track': ClipAudioError.noAudioTrack,
    'unsupported_codec': ClipAudioError.unsupportedCodec,
    'unreadable_file': ClipAudioError.unreadableFile,
    'decode_failed': ClipAudioError.decodeFailed,
    'cancelled': ClipAudioError.cancelled,
  };
}
