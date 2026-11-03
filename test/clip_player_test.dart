// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_player.dart';
import 'package:video_player/video_player.dart';

void main() {
  test(
      '8-bit SDR on Android plays in the texture view, the rest in a '
      'platform view', () {
    const android = TargetPlatform.android;
    const iOS = TargetPlatform.iOS;
    const texture = VideoViewType.textureView;
    const platform = VideoViewType.platformView;
    for (final (on, transfer, bits, view) in const [
      (android, 'sdr', 8, texture),
      (android, 'sdr', 10, platform),
      (android, 'sdr', null, platform),
      (android, 'pq', 10, platform),
      (android, 'hlg', 10, platform),
      (android, null, 8, platform),
      (iOS, 'sdr', 8, platform),
      (iOS, 'pq', 10, platform),
      (iOS, null, null, platform),
    ]) {
      final clip = ClipInfo(
          hasAudio: true,
          durationMs: 1000,
          colorTransfer: transfer,
          bitDepth: bits);
      expect(ClipPlayer.viewTypeFor(clip, on), view,
          reason: '$on $transfer $bits-bit');
    }
  });
}
