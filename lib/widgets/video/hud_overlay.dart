// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../services/video/hud.dart';
import '../../services/video/hud_painter.dart';

/// The overlay's words in the app's language.
extension HudLabelsOf on BuildContext {
  HudLabels get hudLabels => HudLabels(
        total: tr('review.summary.total'),
        first: tr('review.summary.first'),
        average: tr('review.summary.average'),
        fastest: tr('review.summary.fastest'),
        shots: tr('review.summary.shots'),
        penaltyTemplate:
            tr('review.penalty', args: {'seconds': HudLabels.placeholder}),
        locale: dateLocale,
      );
}

/// The overlay over a clip, laid out in the clip's own pixels ([frame])
/// and scaled to the box it fills, so the preview matches the export.
/// [timeMs] is read on every paint, which [repaint] triggers. With
/// [reduceMotion] the clock doesn't pulse (the export still does).
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
    this.reduceMotion = false,
  });

  final Size frame;
  final HudString string;
  final HudOptions options;
  final HudLabels labels;
  final int Function() timeMs;
  final Listenable? repaint;
  final ui.Image? logo;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HudPainter(
          frame: frame,
          string: string,
          options: options,
          labels: labels,
          timeMs: timeMs,
          logo: logo,
          pulse: !reduceMotion,
          repaint: repaint,
        ),
      ),
    );
  }
}

class _HudPainter extends CustomPainter {
  _HudPainter({
    required this.frame,
    required this.string,
    required this.options,
    required this.labels,
    required this.timeMs,
    required this.logo,
    required this.pulse,
    super.repaint,
  });

  final Size frame;
  final HudString string;
  final HudOptions options;
  final HudLabels labels;
  final int Function() timeMs;
  final ui.Image? logo;
  final bool pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty || size.isEmpty) return;
    final layout = HudLayout(frame, options);
    final m =
        HudMoment.at(string, timeMs(), endCard: options.endCard, pulse: pulse);
    canvas.scale(size.width / frame.width);
    canvas
      ..save()
      ..translate(layout.box.left, layout.box.top);
    paintHudBox(canvas, layout, string, options, m, labels, logo: logo);
    canvas.restore();
    if (m.endCard > 0) {
      canvas.translate(layout.card.left, layout.card.top);
      paintEndCard(canvas, layout, string, labels, m.endCard);
    }
  }

  // Cheap, and the string and labels are rebuilt with the page anyway.
  @override
  bool shouldRepaint(_HudPainter old) => true;
}
