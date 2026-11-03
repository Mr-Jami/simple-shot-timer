// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  test('SDR on Android plays in the texture view, the rest in a platform view',
      () {
    const android = TargetPlatform.android;
    const iOS = TargetPlatform.iOS;
    const texture = VideoViewType.textureView;
    const platform = VideoViewType.platformView;
    for (final (on, transfer, view) in const [
      (android, 'sdr', texture),
      (android, 'pq', platform),
      (android, 'hlg', platform),
      (android, null, platform),
      (iOS, 'sdr', platform),
      (iOS, 'pq', platform),
      (iOS, null, platform),
    ]) {
      final clip =
          ClipInfo(hasAudio: true, durationMs: 1000, colorTransfer: transfer);
      expect(ClipPlayer.viewTypeFor(clip, on), view, reason: '$on $transfer');
    }
  });
}
