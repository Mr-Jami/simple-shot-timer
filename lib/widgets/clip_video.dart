// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A clip's picture at [aspectRatio] (from the file, so the box has its
/// size before the first frame), else the decoder's once it knows, else
/// 16:9. Empty until the player is ready.
class ClipVideo extends StatelessWidget {
  const ClipVideo({super.key, required this.player, this.aspectRatio});

  final VideoPlayerController player;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: player,
      builder: (context, value, _) => AspectRatio(
        aspectRatio:
            aspectRatio ?? (value.isInitialized ? value.aspectRatio : 16 / 9),
        child: value.isInitialized
            // A fresh widget per controller: reusing the platform view for
            // another controller freezes the picture.
            ? VideoPlayer(player, key: ObjectKey(player))
            : const SizedBox.expand(),
      ),
    );
  }
}
