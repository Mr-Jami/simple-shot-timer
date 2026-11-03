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
///
/// Only the clock's digits change from frame to frame. The rest is kept in
/// pictures, drawn again when a shot fires or the overlay changes, and the
/// overlay repaints without the page around it.
class HudOverlay extends StatefulWidget {
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
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  final _pictures = _HudPictures();

  // Every rebuild brings a new string, labels and time (they can't be
  // compared), so the pictures are drawn again; the editor rebuilds on
  // edits, not while it plays.
  @override
  void didUpdateWidget(HudOverlay old) {
    super.didUpdateWidget(old);
    _pictures.clear();
  }

  @override
  void dispose() {
    _pictures.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _HudPainter(
            frame: widget.frame,
            string: widget.string,
            options: widget.options,
            labels: widget.labels,
            timeMs: widget.timeMs,
            logo: widget.logo,
            pulse: !widget.reduceMotion,
            pictures: _pictures,
            repaint: widget.repaint,
          ),
        ),
      ),
    );
  }
}

/// Pictures of the parts that change only when a shot fires: the shade and
/// the box without the clock's digits (for the shots fired so far), and the
/// end card.
class _HudPictures {
  ui.Picture? _still;
  int? _fired;
  ui.Picture? _card;

  ui.Picture still(int fired, void Function(Canvas canvas) paint) {
    if (_still == null || fired != _fired) {
      _still?.dispose();
      _still = _record(paint);
      _fired = fired;
    }
    return _still!;
  }

  ui.Picture card(void Function(Canvas canvas) paint) =>
      _card ??= _record(paint);

  void clear() {
    _still?.dispose();
    _card?.dispose();
    _still = _card = null;
  }

  static ui.Picture _record(void Function(Canvas canvas) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    return recorder.endRecording();
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
    required this.pictures,
    super.repaint,
  });

  final Size frame;
  final HudString string;
  final HudOptions options;
  final HudLabels labels;
  final int Function() timeMs;
  final ui.Image? logo;
  final bool pulse;
  final _HudPictures pictures;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty || size.isEmpty) return;
    final layout = HudLayout(frame, options);
    final m =
        HudMoment.at(string, timeMs(), endCard: options.endCard, pulse: pulse);
    final box = layout.box.topLeft;
    canvas
      ..scale(size.width / frame.width)
      ..drawPicture(pictures.still(m.fired, (c) {
        paintHudShade(c, layout);
        c.translate(box.dx, box.dy);
        paintHudBox(c, layout, string, options, m, labels,
            logo: logo, parts: HudParts.still);
      }))
      ..save()
      ..translate(box.dx, box.dy);
    paintHudBox(canvas, layout, string, options, m, labels,
        parts: HudParts.clock);
    canvas.restore();
    paintFaded(
      canvas,
      layout.cardShade,
      m.endCard,
      () => canvas.drawPicture(pictures
          .card((c) => paintEndCard(c, layout, string, labels, logo: logo))),
    );
  }

  // A new painter comes only with a rebuilt overlay, which also cleared the
  // pictures.
  @override
  bool shouldRepaint(_HudPainter old) => true;
}
