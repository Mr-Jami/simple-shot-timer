// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/video/clip_signal.dart';
import 'timeline_controller.dart';

/// The whole timeline (the clip, or the analysed part of a long one) at a
/// glance: its loudness (shots stand out), a tick per marker, and the
/// stretch the timeline shows. A tap jumps there; a drag along it scrubs.
class TimelineMinimap extends StatelessWidget {
  const TimelineMinimap({
    super.key,
    required this.controller,
    required this.levels,
    required this.originMs,
    required this.frameMs,
    required this.markers,
    required this.onJump,
    required this.onScrub,
  });

  static const double height = 28;

  final TimelineController controller;

  /// Loudness of every spectrogram frame.
  final Float32List levels;

  /// Clip time of the first frame, and how long one frame lasts.
  final int originMs;
  final double frameMs;
  final List<int> markers;

  /// The user tapped this clip time.
  final ValueChanged<int> onJump;

  /// The user's finger is dragging along at this clip time.
  final ValueChanged<int> onScrub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final from = controller.startMs;
      final to = controller.endMs;
      int msAt(double x) =>
          (from + x / width * (to - from)).clamp(from, to).round();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => onJump(msAt(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) => onScrub(msAt(d.localPosition.dx)),
        child: CustomPaint(
          size: Size(width, height),
          painter: _MinimapPainter(
            controller: controller,
            buckets: bucketMax(levels, width.floor().clamp(1, 4096)),
            originMs: originMs,
            frameMs: frameMs,
            frames: levels.length,
            markers: markers,
            ink: scheme.onSurface,
            dim: scheme.onSurfaceVariant,
            track: scheme.surfaceContainerHighest,
          ),
        ),
      );
    });
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.controller,
    required this.buckets,
    required this.originMs,
    required this.frameMs,
    required this.frames,
    required this.markers,
    required this.ink,
    required this.dim,
    required this.track,
  }) : super(repaint: controller);

  final TimelineController controller;
  final Float32List buckets;
  final int originMs;
  final double frameMs;
  final int frames;
  final List<int> markers;
  final Color ink;
  final Color dim;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final from = controller.startMs;
    final span = (controller.endMs - from).toDouble();
    if (span <= 0) return;
    double xOf(num ms) => (ms - from) / span * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = track,
    );

    // Loudness: the buckets cover the frames, which start at originMs.
    if (buckets.isNotEmpty) {
      var low = buckets.first;
      var high = buckets.first;
      for (final b in buckets) {
        if (b < low) low = b;
        if (b > high) high = b;
      }
      final span = (high - low) == 0 ? 1 : high - low;
      final x0 = xOf(originMs);
      final x1 = xOf(originMs + frames * frameMs);
      final step = (x1 - x0) / buckets.length;
      final bar = Paint()..color = dim.withValues(alpha: 0.6);
      for (var i = 0; i < buckets.length; i++) {
        final h = (buckets[i] - low) / span * (size.height - 6);
        canvas.drawRect(
          Rect.fromLTWH(
              x0 + i * step, size.height - 3 - h, step.clamp(1, 4), h),
          bar,
        );
      }
    }

    final tick = Paint()
      ..color = ink
      ..strokeWidth = 1;
    for (final m in markers) {
      final x = xOf(m);
      canvas.drawLine(Offset(x, 2), Offset(x, 7), tick);
    }

    // The stretch the timeline shows, with the playhead in it.
    final halfMs = controller.viewportWidth / 2 / controller.pxPerSecond * 1000;
    final at = controller.playheadMs;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(xOf(at - halfMs), 0, xOf(at + halfMs), size.height),
        const Radius.circular(6),
      ),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(xOf(at), 0),
      Offset(xOf(at), size.height),
      Paint()
        ..color = ink
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.buckets != buckets || old.markers != markers || old.ink != ink;
}
