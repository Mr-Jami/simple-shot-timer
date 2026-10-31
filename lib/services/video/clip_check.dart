// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'clip_audio_source.dart';

/// Why a clip can't become a string. Each has its own message.
enum ClipProblem {
  /// No audio track, or one without sound in it.
  noSound,

  /// Recorded in slow motion: the sound is missing or slowed down.
  slowMotion,

  /// A time-lapse or hyperlapse: no usable sound.
  timeLapse,

  /// The phone can't decode the sound (e.g. Dolby Digital on some Androids),
  /// or its decoder failed part-way.
  unreadableSound,

  /// Not a video the phone can play.
  unsupportedVideo,

  /// The file is gone or unreadable.
  unreadableFile,

  /// Too short to hold a beep and a shot.
  tooShort,

  /// The phone's storage is full.
  noSpace,

  /// Anything else, such as no document picker on the phone.
  failed,
}

const int _minClipMs = 1000;

/// What's wrong with [info] before any decoding, or null when it can be
/// analysed (clips over three minutes a part at a time).
ClipProblem? checkClip(ClipInfo info) {
  if (info.videoMime == null) return ClipProblem.unsupportedVideo;
  final capture = info.captureFrameRate;
  final playback = info.frameRate;
  if (capture != null && playback != null && playback > 0) {
    if (capture > playback * 1.5) return ClipProblem.slowMotion;
    if (capture < playback / 2) return ClipProblem.timeLapse;
  }
  if (!info.hasAudio) return ClipProblem.noSound;
  if (info.durationMs < _minClipMs) return ClipProblem.tooShort;
  return null;
}

ClipProblem problemFor(ClipAudioError error) => switch (error) {
      ClipAudioError.noAudioTrack => ClipProblem.noSound,
      ClipAudioError.unsupportedCodec ||
      ClipAudioError.decodeFailed =>
        ClipProblem.unreadableSound,
      ClipAudioError.unreadableFile => ClipProblem.unreadableFile,
      ClipAudioError.unsupportedFile => ClipProblem.unsupportedVideo,
      ClipAudioError.noSpace => ClipProblem.noSpace,
      ClipAudioError.unavailable ||
      ClipAudioError.cancelled =>
        ClipProblem.failed,
    };
