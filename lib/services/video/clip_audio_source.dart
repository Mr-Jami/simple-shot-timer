// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/cancel_token.dart';

/// Whether [platform] can read a clip's sound: Android and iOS. Elsewhere
/// the Video tab stays hidden.
bool clipAudioAvailableOn(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

/// Why a clip's sound could not be read.
enum ClipAudioError {
  /// The file has no audio track (a screen recording, some time-lapses), or
  /// one that decodes to nothing.
  noAudioTrack,

  /// The phone has no decoder for the clip's sound (e.g. Dolby Digital on
  /// some Android phones).
  unsupportedCodec,

  /// The file is missing or can't be read.
  unreadableFile,

  /// The file is there but won't open: cut short (no index) or a container
  /// this phone can't read.
  unsupportedFile,

  /// The phone's storage ran full while copying or decoding.
  noSpace,

  /// The platform decoder failed part-way.
  decodeFailed,

  /// No decoder or picker on this platform, or the platform side refused
  /// the call.
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

/// What the platform knows about a clip before decoding it. `checkClip`
/// reads the audio, video and frame-rate fields; the editor and the export
/// read the displayed size, the frame rate and the recording date. The
/// audio codec, rotation and colour transfer are diagnostics for the
/// on-device analysis report (`integration_test/clip_analysis_test.dart`).
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

  /// Width over height as displayed, when the file says.
  double? get aspectRatio =>
      width != null && height != null && height! > 0 ? width! / height! : null;
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
  /// picture (of a window too: it counts from the clip's start).
  final int firstSampleTimeUs;

  double get durationSeconds => sampleCount / sampleRate;
}

/// Reads a clip's sound for the analyzer. Implemented by the platform in
/// `android/.../ClipAudioChannel.kt` and `ios/Runner/ClipAudioChannel.swift`.
abstract interface class ClipAudioSource {
  /// Reads [path]'s container metadata without decoding anything.
  Future<ClipInfo> probe(String path);

  /// Decodes [path]'s audio track to [outputPath], from [startMs] to [endMs]
  /// (null: the end) of the clip. Of several tracks it takes the mono or
  /// stereo AAC one (iPhone spatial-audio clips add a four-channel track),
  /// else the first. [onProgress] gets 0..1 while it runs; [cancel] stops
  /// it, and it then throws [ClipAudioError.cancelled] and leaves no file.
  Future<DecodedAudio> decode(
    String path, {
    required String outputPath,
    int startMs = 0,
    int? endMs,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  });

  /// The loudness of [path]'s whole sound for Choose the part: the RMS
  /// (0..1) of every [bucketMs], handed to [onValues] in batches as the scan
  /// goes, the first at index [from]. Returns how many buckets there were.
  Future<int> scanLoudness(
    String path, {
    int bucketMs = 250,
    required void Function(int from, List<double> values) onValues,
    CancelToken? cancel,
  });

  /// Frames at [timesMs] for the Choose-the-part filmstrip, as JPEGs about
  /// [width] pixels wide, each handed to [onFrame] once ready. Frames the
  /// phone can't read are skipped.
  Future<void> thumbnails(
    String path, {
    required List<int> timesMs,
    int width = 160,
    required void Function(int index, Uint8List jpeg) onFrame,
    CancelToken? cancel,
  });
}

/// [ClipAudioSource] over the `cc.jami.simpleshottimer/clip_audio` channel
/// (`ClipAudioChannel.kt`, `ClipAudioChannel.swift`).
class ChannelClipAudioSource implements ClipAudioSource {
  ChannelClipAudioSource({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('cc.jami.simpleshottimer/clip_audio') {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  final MethodChannel _channel;

  /// What each running job does with the messages it sends back
  /// (`progress`, `loudness`, `thumbnail`).
  final _jobs = <int, void Function(String method, Map<Object?, Object?>)>{};
  static var _nextJobId = 1;

  Future<void> _onPlatformCall(MethodCall call) async {
    final args = call.arguments as Map<Object?, Object?>;
    _jobs[args['jobId']]?.call(call.method, args);
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
    int startMs = 0,
    int? endMs,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    final m = await _job(
      'decode',
      {
        'path': path,
        'outputPath': outputPath,
        'startMs': startMs,
        'endMs': endMs,
      },
      cancel: cancel,
      onMessage: (method, args) {
        if (method == 'progress') {
          onProgress?.call((args['fraction'] as num).toDouble());
        }
      },
    );
    return DecodedAudio(
      pcmPath: outputPath,
      sampleRate: m['sampleRate'] as int,
      channelCount: m['channelCount'] as int,
      sampleCount: m['sampleCount'] as int,
      firstSampleTimeUs: m['firstSampleTimeUs'] as int? ?? 0,
    );
  }

  @override
  Future<int> scanLoudness(
    String path, {
    int bucketMs = 250,
    required void Function(int from, List<double> values) onValues,
    CancelToken? cancel,
  }) async {
    final m = await _job(
      'loudness',
      {'path': path, 'bucketMs': bucketMs},
      cancel: cancel,
      onMessage: (method, args) {
        if (method != 'loudness') return;
        onValues(args['from'] as int, [
          for (final v in args['values'] as List<Object?>)
            (v as num).toDouble(),
        ]);
      },
    );
    return m['buckets'] as int? ?? 0;
  }

  @override
  Future<void> thumbnails(
    String path, {
    required List<int> timesMs,
    int width = 160,
    required void Function(int index, Uint8List jpeg) onFrame,
    CancelToken? cancel,
  }) =>
      _job(
        'thumbnails',
        {'path': path, 'timesMs': timesMs, 'width': width},
        cancel: cancel,
        onMessage: (method, args) {
          if (method == 'thumbnail') {
            onFrame(args['index'] as int, args['bytes'] as Uint8List);
          }
        },
      );

  /// Runs [method] as a job the platform reports on and [cancel] can stop;
  /// a token already cancelled never starts it.
  Future<Map<Object?, Object?>> _job(
    String method,
    Map<String, Object?> arguments, {
    required void Function(String method, Map<Object?, Object?> args) onMessage,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const ClipAudioException(ClipAudioError.cancelled);
    }
    final jobId = _nextJobId++;
    _jobs[jobId] = onMessage;
    unawaited(cancel?.whenCancelled.then((_) async {
      try {
        await _channel.invokeMethod<void>('cancel', {'jobId': jobId});
      } on Exception {
        // The job reports its own end.
      }
    }));
    try {
      return await _invoke(method, {...arguments, 'jobId': jobId});
    } finally {
      _jobs.remove(jobId);
    }
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
    'unsupported_file': ClipAudioError.unsupportedFile,
    'no_space': ClipAudioError.noSpace,
    'decode_failed': ClipAudioError.decodeFailed,
    'cancelled': ClipAudioError.cancelled,
  };
}
