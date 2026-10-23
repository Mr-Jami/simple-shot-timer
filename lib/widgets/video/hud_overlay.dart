// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/video/hud.dart';
import 'hud_painter.dart';

/// The overlay over a clip, laid out in the clip's own pixels ([frame])
/// and scaled to the box it fills, so the preview matches the export.
/// [timeMs] is read on every paint, which [repaint] triggers.
class HudOverlay extends StatelessWidget {
  const HudOverlay({
    super.key,
    required this.frame,
    required this.string,
    required this.options,
    required this.labels,
    required this.timeMs,
    this.repaint,
    this.logo,
  });

  final Size frame;
  final HudString string;
  final HudOptions options;
  final HudLabels labels;
  final int Function() timeMs;
  final Listenable? repaint;
  final ui.Image? logo;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HudPainter(this),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  _HudPainter(this.overlay) : super(repaint: overlay.repaint);

  final HudOverlay overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final o = overlay;
    if (o.frame.isEmpty || size.isEmpty) return;
    final layout = HudLayout(o.frame, o.options);
    final m = HudMoment.at(o.string, o.timeMs(), endCard: o.options.endCard);
    canvas
      ..save()
      ..scale(size.width / o.frame.width)
      ..save()
      ..translate(layout.box.left, layout.box.top);
    paintHudBox(canvas, layout, o.string, o.options, m, o.labels, logo: o.logo);
    canvas.restore();
    if (m.endCard > 0) {
      canvas.translate(layout.card.left, layout.card.top);
      paintEndCard(canvas, layout, o.string, o.labels, m.endCard);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HudPainter old) =>
      old.overlay.frame != overlay.frame ||
      old.overlay.string != overlay.string ||
      old.overlay.options != overlay.options ||
      old.overlay.labels != overlay.labels ||
      old.overlay.logo != overlay.logo;
}
