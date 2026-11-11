// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'clip_audio_source.dart';
import 'throttled_seeker.dart';

/// A clip's video for the editor and Choose the part, in the view
/// [viewTypeFor] picks. Seeks that follow a finger go through a
/// [ThrottledSeeker].
class ClipPlayer extends VideoPlayerController {
  ClipPlayer(String path, {required ClipInfo info})
      : super.file(File(path),
            viewType: viewTypeFor(info, defaultTargetPlatform));

  /// The texture view washes out HDR and garbles 4K 10-bit video, so
  /// those clips, and any whose colours or bit depth the file doesn't name,
  /// play in a platform view. On Android that is a SurfaceView, which puts
  /// the screen into Hybrid Composition: Flutter then draws on the main
  /// thread and every frame also goes through Android's renderer. So there,
  /// 8-bit SDR clips play in the texture view.
  @visibleForTesting
  static VideoViewType viewTypeFor(ClipInfo info, TargetPlatform platform) =>
      platform == TargetPlatform.android &&
              info.colorTransfer == 'sdr' &&
              info.bitDepth == 8
          ? VideoViewType.textureView
          : VideoViewType.platformView;

  late final _seeker = ThrottledSeeker(seekTo);

  /// Follows a moving finger: one seek in flight, spaced out.
  void scrub(int ms) => _seeker.scrub(Duration(milliseconds: ms));

  /// Lands exactly on [ms] as soon as the seek in flight is done.
  Future<void> settle(int ms) => _seeker.release(Duration(milliseconds: ms));

  var _pauses = 0;

  /// Waits until the video is where it was last sent, for a play that starts
  /// from there: sooner, it would play from wherever the last [scrub] left
  /// it and then jump. False if [pause] was called meanwhile: whatever
  /// called it (a touch on the timeline, leaving the screen, the app going
  /// to the background) called that play off.
  ///
  /// Waits a second at most: a seek the platform never answers (on iOS, one
  /// to the exact end of some files) must not leave Play dead.
  Future<bool> landed() async {
    final pauses = _pauses;
    try {
      await _seeker.landed.timeout(const Duration(seconds: 1));
    } on Exception {
      // A seek that failed, or hasn't landed in time, leaves the video
      // where it is: it plays from there rather than not at all.
    }
    return pauses == _pauses;
  }

  @override
  Future<void> pause() {
    _pauses++;
    return super.pause();
  }
}
