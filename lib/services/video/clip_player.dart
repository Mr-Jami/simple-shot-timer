// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:video_player/video_player.dart';

import 'throttled_seeker.dart';

/// A clip's video for the editor and Choose the part. It plays in a
/// platform view: the texture view washes out HDR and garbles 4K 10-bit
/// clips. Seeks that follow a finger go through a [ThrottledSeeker].
class ClipPlayer extends VideoPlayerController {
  ClipPlayer(String path)
      : super.file(File(path), viewType: VideoViewType.platformView);

  late final _seeker = ThrottledSeeker(seekTo);

  /// Follows a moving finger: one seek in flight, spaced out.
  void scrub(int ms) => _seeker.scrub(Duration(milliseconds: ms));

  /// Lands exactly on [ms] as soon as the seek in flight is done.
  Future<void> settle(int ms) => _seeker.release(Duration(milliseconds: ms));
}
