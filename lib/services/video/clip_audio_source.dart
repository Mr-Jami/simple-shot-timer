// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/services.dart';

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
    this.colorTransfer,
    this.frameRate,
    this.creationTime,
  });

  final bool hasAudio;
  final int durationMs;
  final String? audioMime;
  final String? videoMime;
  final int rotationDegrees;

  /// 'sdr', 'pq' (HDR10, Dolby Vision) or 'hlg'; null when unknown.
  final String? colorTransfer;
  final double? frameRate;

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
  /// four-channel track), else the first.
  Future<DecodedAudio> decode(String path, {required String outputPath});
}

/// [ClipAudioSource] over the `cc.jami.simpleshottimer/clip_audio` channel
/// (Android: `ClipAudioChannel.kt`).
class ChannelClipAudioSource implements ClipAudioSource {
  ChannelClipAudioSource({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('cc.jami.simpleshottimer/clip_audio');

  final MethodChannel _channel;

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
      colorTransfer: m['colorTransfer'] as String?,
      frameRate: (m['frameRate'] as num?)?.toDouble(),
      creationTime: created == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
    );
  }

  @override
  Future<DecodedAudio> decode(String path, {required String outputPath}) async {
    final m =
        await _invoke('decode', {'path': path, 'outputPath': outputPath});
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
      throw ClipAudioException(_errors[e.code] ?? ClipAudioError.decodeFailed,
          e.message);
    } on MissingPluginException {
      throw const ClipAudioException(ClipAudioError.unavailable);
    }
  }

  static const _errors = {
    'no_audio_track': ClipAudioError.noAudioTrack,
    'unsupported_codec': ClipAudioError.unsupportedCodec,
    'unreadable_file': ClipAudioError.unreadableFile,
    'decode_failed': ClipAudioError.decodeFailed,
  };
}
