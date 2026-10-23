// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'clip_audio_source.dart';
import 'hud.dart';

/// What an export covers and how big it is: the string from [leadInMs]
/// before START to [tailMs] after the last shot (inside the analysed
/// range), at most 1080 on its short side and 60 frames a second, H.264.
class ExportPlan {
  factory ExportPlan(
    HudString s,
    ClipInfo info, {
    required int fromMs,
    required int toMs,
  }) {
    final width = (info.width ?? 1920).toDouble();
    final height = (info.height ?? 1080).toDouble();
    final short = math.min(width, height);
    final scale = short > maxShortSide ? maxShortSide / short : 1.0;
    final frame = Size(_even(width * scale), _even(height * scale));
    final sourceFps = info.frameRate ?? 30;
    final fps = math.min(sourceFps, fpsLimit.toDouble());
    // 12 Mb/s for 1080p30, more for 60 fps, less for smaller frames.
    final pixels = frame.width * frame.height / (1920 * 1080);
    final bitrate =
        (12e6 * pixels * (fps > 40 ? 4 / 3 : 1)).clamp(2e6, 16e6).round();
    return ExportPlan._(
      startMs: math.max(fromMs, s.startMs - leadInMs),
      endMs: math.min(toMs, s.endMs + tailMs),
      frame: frame,
      shortSide: scale < 1 ? maxShortSide : null,
      fps: fps,
      maxFps: sourceFps > fpsLimit + 0.5 ? fpsLimit.toDouble() : null,
      bitrate: bitrate,
    );
  }

  const ExportPlan._({
    required this.startMs,
    required this.endMs,
    required this.frame,
    required this.shortSide,
    required this.fps,
    required this.maxFps,
    required this.bitrate,
  });

  static const int leadInMs = 3000;
  static const int tailMs = 4000;
  static const int maxShortSide = 1080;
  static const int fpsLimit = 60;

  /// The exported range, in clip time.
  final int startMs;
  final int endMs;

  /// The exported frame, upright.
  final Size frame;

  /// The short side to scale to; null keeps the source's size.
  final int? shortSide;

  /// Frames a second of the export (the overlay draws one image each).
  final double fps;

  /// Set when the source runs faster than [fpsLimit].
  final double? maxFps;
  final int bitrate;

  /// `SimpleShotTimer_2026-10-23_21.47s.mp4`.
  static String fileName(DateTime date, int totalMs) {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${date.year}-${two(date.month)}-${two(date.day)}';
    return 'SimpleShotTimer_${day}_${(totalMs / 1000).toStringAsFixed(2)}s.mp4';
  }

  static double _even(double v) => (v / 2).round() * 2.0;
}
