// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import 'spectrogram_tiles.dart';
import 'timeline_controller.dart';

enum TimelineMarkerKind { start, shot }

/// A marker drawn on the timeline, in clip milliseconds.
class TimelineMarker {
  const TimelineMarker({
    required this.ms,
    required this.kind,
    this.id,
    this.ordinal,
    this.manual = false,
    this.active = true,
    this.selected = false,
  });

  final int ms;
  final TimelineMarkerKind kind;

  /// The shot's id in the editor; null for START.
  final int? id;

  /// Shot number in the string; null for shots outside it.
  final int? ordinal;
  final bool manual;

  /// Inside the string (after START, up to the last shot).
  final bool active;
  final bool selected;
}

/// The editor's timeline: shot badges on top, the spectrogram in the
/// middle, splits underneath, and a fixed playhead the clip scrolls under.
/// One finger drags it 1:1, two fingers zoom around themselves, a flick
/// flings it (unless [flingEnabled] is off), and a tap picks the nearest
/// marker.
class ShotTimeline extends StatefulWidget {
  const ShotTimeline({
    super.key,
    required this.controller,
    required this.tiles,
    required this.originMs,
    required this.markers,
    required this.startLabel,
    required this.onTouch,
    required this.onRelease,
    required this.onTapMarker,
    required this.onTapEmpty,
    this.flingEnabled = true,
  });

  static const double badgeHeight = 28;
  static const double bandHeight = 84;
  static const double splitHeight = 20;
  static const double height = badgeHeight + bandHeight + splitHeight;
  static const double _tapSlop = 24;

  final TimelineController controller;
  final SpectrogramTiles tiles;

  /// Clip time of the spectrogram's first frame.
  final int originMs;
  final List<TimelineMarker> markers;

  /// The START marker's badge, in the app's language.
  final String startLabel;
  final VoidCallback onTouch;
  final VoidCallback onRelease;
  final ValueChanged<TimelineMarker> onTapMarker;
  final VoidCallback onTapEmpty;
  final bool flingEnabled;

  @override
  State<ShotTimeline> createState() => _ShotTimelineState();
}

class _ShotTimelineState extends State<ShotTimeline> {
  /// Fingers now, and the most in this gesture (a pinch never flings).
  var _pointers = 0;
  var _maxPointers = 0;

  /// Where the finger touched down, and where the drag is measured from.
  double? _downX;
  var _anchorX = 0.0;

  TimelineController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      controller.viewportWidth = width;
      return Listener(
        onPointerDown: (e) => _downX ??= e.localPosition.dx,
        onPointerUp: (_) => _downX = null,
        onPointerCancel: (_) => _downX = null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _pointers = _maxPointers = details.pointerCount;
            // From the touch, not from where the drag was recognised: the
            // clip stays glued to where it was grabbed.
            _anchorX = _downX ?? details.localFocalPoint.dx;
            widget.onTouch();
            controller.startDrag();
          },
          onScaleUpdate: (details) {
            if (details.pointerCount != _pointers) {
              // A finger joined or left: measure from here on, no jump.
              _pointers = details.pointerCount;
              if (_pointers > _maxPointers) _maxPointers = _pointers;
              _anchorX = details.localFocalPoint.dx;
              controller.startDrag();
            }
            if (details.pointerCount >= 2) {
              controller.zoom(
                  details.scale, details.localFocalPoint.dx - width / 2);
            } else {
              controller.dragTo(details.localFocalPoint.dx - _anchorX);
            }
          },
          onScaleEnd: (details) {
            controller.endDrag(
              details.velocity.pixelsPerSecond.dx,
              fling: widget.flingEnabled && _maxPointers < 2,
            );
            _pointers = _maxPointers = 0;
            widget.onRelease();
          },
          onTapUp: (details) {
            final tapped = _nearest(details.localPosition.dx - width / 2);
            if (tapped == null) {
              widget.onTapEmpty();
            } else {
              widget.onTapMarker(tapped);
            }
          },
          child: CustomPaint(
            size: Size(width, ShotTimeline.height),
            painter: _TimelinePainter(
              controller: controller,
              tiles: widget.tiles,
              originMs: widget.originMs,
              markers: widget.markers,
              startLabel: widget.startLabel,
              ink: scheme.onSurface,
              paper: scheme.surface,
              dim: scheme.onSurfaceVariant,
              textStyle: theme.textTheme.labelSmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
    });
  }

  TimelineMarker? _nearest(double dxFromPlayhead) {
    final tapMs =
        controller.displayMs + dxFromPlayhead / controller.pxPerSecond * 1000;
    final slopMs = ShotTimeline._tapSlop / controller.pxPerSecond * 1000;
    TimelineMarker? best;
    var bestDistance = slopMs;
    for (final m in widget.markers) {
      final d = (m.ms - tapMs).abs();
      if (d <= bestDistance) {
        best = m;
        bestDistance = d;
      }
    }
    return best;
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.controller,
    required this.tiles,
    required this.originMs,
    required this.markers,
    required this.startLabel,
    required this.ink,
    required this.paper,
    required this.dim,
    required this.textStyle,
  }) : super(repaint: Listenable.merge([controller, tiles]));

  final TimelineController controller;
  final SpectrogramTiles tiles;
  final int originMs;
  final List<TimelineMarker> markers;
  final String startLabel;
  final Color ink;
  final Color paper;
  final Color dim;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.width / 2;
    final pps = controller.pxPerSecond;
    final at = controller.displayMs;
    double xOf(num ms) => centre + (ms - at) / 1000 * pps;
    const top = ShotTimeline.badgeHeight;
    const bottom = top + ShotTimeline.bandHeight;
    final band = Rect.fromLTRB(0, top, size.width, bottom);

    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    _paintSpectrogram(canvas, band, xOf);

    // Outside the string (before START, after the last shot) is dimmed.
    final active = [
      for (final m in markers)
        if (m.active) m.ms
    ]..sort();
    final start =
        markers.where((m) => m.kind == TimelineMarkerKind.start).firstOrNull;
    final shade = Paint()..color = paper.withValues(alpha: 0.55);
    if (start != null) {
      canvas.drawRect(Rect.fromLTRB(0, top, xOf(start.ms), bottom), shade);
      final end = active.isEmpty ? start.ms : active.last;
      canvas.drawRect(Rect.fromLTRB(xOf(end), top, size.width, bottom), shade);
    }

    _paintSplits(canvas, size, xOf);
    for (final m in markers) {
      final x = xOf(m.ms);
      if (x < -20 || x > size.width + 20) continue;
      _paintMarker(canvas, m, x, top, bottom);
    }

    // The playhead, from below the badges so the one on it stays legible.
    final playhead = Paint()
      ..color = ink
      ..strokeWidth = 2;
    canvas.drawLine(Offset(centre, top), Offset(centre, size.height), playhead);
    canvas.drawPath(
      Path()
        ..moveTo(centre - 6, top)
        ..lineTo(centre + 6, top)
        ..lineTo(centre, top + 7)
        ..close(),
      Paint()..color = ink,
    );
  }

  void _paintSpectrogram(Canvas canvas, Rect band, double Function(num) xOf) {
    final s = tiles.spectrogram;
    final fps = s.framesPerSecond;
    if (fps <= 0 || s.frameCount == 0) return;
    double msOfFrame(num frame) => originMs + frame / fps * 1000;
    final firstVisible = ((controller.displayMs -
                band.width / 2 / controller.pxPerSecond * 1000 -
                originMs) /
            1000 *
            fps)
        .floor();
    final lastVisible =
        firstVisible + (band.width / controller.pxPerSecond * fps).ceil() + 1;
    canvas.save();
    canvas.clipRect(band);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final firstTile =
        (firstVisible ~/ tiles.tileFrames).clamp(0, tiles.tileCount);
    final lastTile =
        (lastVisible ~/ tiles.tileFrames).clamp(0, tiles.tileCount - 1);
    for (var i = firstTile; i <= lastTile; i++) {
      final image = tiles.tile(i);
      if (image == null) continue;
      final from = i * tiles.tileFrames;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTRB(xOf(msOfFrame(from)), band.top,
            xOf(msOfFrame(from + image.width)), band.bottom),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintMarker(
      Canvas canvas, TimelineMarker m, double x, double top, double bottom) {
    final colour = m.active || m.kind == TimelineMarkerKind.start ? ink : dim;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = colour.withValues(alpha: m.selected ? 1 : 0.7)
        ..strokeWidth = m.selected ? 2.5 : 1.25,
    );
    const r = 11.0;
    final c = Offset(x, ShotTimeline.badgeHeight / 2);
    if (m.kind == TimelineMarkerKind.start) {
      _text(canvas, startLabel, c,
          textStyle.copyWith(color: ink, fontWeight: FontWeight.w700));
      return;
    }
    final filled = !m.manual || m.selected;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color =
            m.selected ? ink : (filled ? colour.withValues(alpha: 0.85) : paper)
        ..style = PaintingStyle.fill,
    );
    if (!filled || m.selected) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      );
    }
    _text(
      canvas,
      m.ordinal?.toString() ?? '·',
      c,
      textStyle.copyWith(
          color: filled ? paper : colour, fontWeight: FontWeight.w700),
    );
  }

  void _paintSplits(Canvas canvas, Size size, double Function(num) xOf) {
    final start =
        markers.where((m) => m.kind == TimelineMarkerKind.start).firstOrNull;
    final shots = [
      for (final m in markers)
        if (m.kind == TimelineMarkerKind.shot && m.active) m.ms,
    ]..sort();
    final points = [if (start != null) start.ms, ...shots];
    final y = size.height - ShotTimeline.splitHeight / 2;
    for (var i = 1; i < points.length; i++) {
      final a = xOf(points[i - 1]);
      final b = xOf(points[i]);
      if (b < 0 || a > size.width) continue;
      final label = ((points[i] - points[i - 1]) / 1000).toStringAsFixed(2);
      final painter = _layout(label, textStyle.copyWith(color: dim));
      if (b - a < painter.width + 8) continue;
      painter.paint(
          canvas, Offset((a + b - painter.width) / 2, y - painter.height / 2));
    }
  }

  TextPainter _layout(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();

  void _text(Canvas canvas, String text, Offset centre, TextStyle style) {
    final painter = _layout(text, style);
    painter.paint(
        canvas, centre - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.markers != markers ||
      old.startLabel != startLabel ||
      old.tiles != tiles ||
      old.ink != ink ||
      old.paper != paper ||
      old.originMs != originMs;
}
