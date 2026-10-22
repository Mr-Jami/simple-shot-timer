// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'clip_audio_source.dart';

/// Why a clip can't become a string. Each has its own message.
enum ClipProblem {
  /// No audio track, or one without sound in it.
  noSound,

  /// The phone can't decode the sound (e.g. Dolby Digital on some Androids).
  unreadableSound,

  /// Not a video the phone can play.
  unsupportedVideo,

  /// The file is gone or unreadable.
  unreadableFile,

  /// Too short to hold a beep and a shot.
  tooShort,

  /// Longer than one analysed part (until Choose the part exists).
  tooLong,

  /// Anything else that failed while reading the sound.
  failed,
}

/// The longest stretch of a clip that is analysed at once.
const int maxClipPartMs = 3 * 60 * 1000;

const int _minClipMs = 1000;

/// What's wrong with [info] before any decoding, or null when it can be
/// analysed.
ClipProblem? checkClip(ClipInfo info) {
  if (info.videoMime == null) return ClipProblem.unsupportedVideo;
  if (!info.hasAudio) return ClipProblem.noSound;
  if (info.durationMs < _minClipMs) return ClipProblem.tooShort;
  if (info.durationMs > maxClipPartMs) return ClipProblem.tooLong;
  return null;
}

ClipProblem problemFor(ClipAudioError error) => switch (error) {
      ClipAudioError.noAudioTrack => ClipProblem.noSound,
      ClipAudioError.unsupportedCodec => ClipProblem.unreadableSound,
      ClipAudioError.unreadableFile => ClipProblem.unreadableFile,
      ClipAudioError.decodeFailed ||
      ClipAudioError.unavailable =>
        ClipProblem.failed,
    };
