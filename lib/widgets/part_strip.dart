// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/video/clip_signal.dart';
import '../services/video/part_window.dart';
import '../utils/motion.dart';

/// What a drag on the [PartStrip] holds.
enum PartEdge { start, end, whole }

/// Choose the part's strip: a filmstrip of a long clip, its loudness
/// underneath (filled in as the scan goes; bursts of shots stand out as
/// spikes), and the window to analyse framed over both. Drag the window to
/// move it, its handles to resize it, or tap outside it to centre it there.
/// A window moved from outside (the scan placing it on the loudest stretch)
/// glides there unless [reduceMotion].
class PartStrip extends StatefulWidget {
  const PartStrip({
    super.key,
    required this.durationMs,
    required this.window,
    required this.loudness,
    required this.bucketMs,
    required this.thumbnails,
    required this.onChanged,
    this.onChangeEnd,
    this.reduceMotion = false,
    this.semanticLabel,
  });

  static const double filmHeight = 56;
  static const double levelHeight = 32;
  static const double gap = 4;
  static const double handleWidth = 14;
  static const double height = filmHeight + gap + levelHeight;

  final int durationMs;
  final PartWindow window;
  final List<double> loudness;
  final int bucketMs;
  final List<Uint8List?> thumbnails;

  /// The window as the user drags it, and which part of it they hold;
  /// [onChangeEnd] follows once a gesture that changed it ends.
  final void Function(PartWindow window, PartEdge edge) onChanged;
  final VoidCallback? onChangeEnd;
  final bool reduceMotion;

  /// Read out for the window, e.g. "Part from 1:20 to 4:20".
  final String? semanticLabel;

  @override
  State<PartStrip> createState() => _PartStripState();
}

class _PartStripState extends State<PartStrip>
    with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(
    vsync: this,
    duration: kMotionMedium,
  )..addListener(() => setState(() {}));
  late PartWindow _from = widget.window;

  PartEdge? _held;
  late PartWindow _grabbed;
  double _downX = 0;

  /// The gesture under way has moved the window.
  var _moved = false;

  void _change(PartWindow window, PartEdge edge) {
    _moved = true;
    widget.onChanged(window, edge);
  }

  /// Screen readers move the window ten seconds at a time.
  void _step(int ms) {
    widget.onChanged(
        widget.window.movedBy(ms, widget.durationMs), PartEdge.whole);
    widget.onChangeEnd?.call();
  }

  /// The window as drawn: gliding from [_from] to the widget's while
  /// [_glide] runs.
  PartWindow get _shown {
    final to = widget.window;
    if (!_glide.isAnimating) return to;
    final t = Curves.easeOutCubic.transform(_glide.value);
    int lerp(int a, int b) => (a + (b - a) * t).round();
    return PartWindow(
        lerp(_from.startMs, to.startMs), lerp(_from.endMs, to.endMs));
  }

  @override
  void didUpdateWidget(PartStrip old) {
    super.didUpdateWidget(old);
    if (old.window != widget.window && _held == null && !widget.reduceMotion) {
      _from = old.window;
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final msPerPx = widget.durationMs / width;
      final window = _shown;
      double xOf(int ms) => ms / msPerPx;

      void down(double x) {
        _glide.stop();
        _downX = x;
        _grabbed = widget.window;
        final left = xOf(_grabbed.startMs);
        final right = xOf(_grabbed.endMs);
        // Handles win over the middle, with a finger's width of slack.
        const reach = PartStrip.handleWidth + 12;
        if ((x - left).abs() <= reach && x <= (left + right) / 2) {
          _held = PartEdge.start;
        } else if ((x - right).abs() <= reach) {
          _held = PartEdge.end;
        } else if (x > left && x < right) {
          _held = PartEdge.whole;
        } else {
          // Outside: centre the window on the finger, then carry it.
          final centre = (x * msPerPx).round();
          _grabbed = _grabbed.movedBy(
              centre - (_grabbed.startMs + _grabbed.lengthMs ~/ 2),
              widget.durationMs);
          _held = PartEdge.whole;
          _change(_grabbed, PartEdge.whole);
        }
      }

      void move(double x) {
        final delta = ((x - _downX) * msPerPx).round();
        final next = switch (_held) {
          PartEdge.start => _grabbed.withStart(_grabbed.startMs + delta),
          PartEdge.end =>
            _grabbed.withEnd(_grabbed.endMs + delta, widget.durationMs),
          PartEdge.whole || null => _grabbed.movedBy(delta, widget.durationMs),
        };
        if (next != widget.window) _change(next, _held ?? PartEdge.whole);
      }

      void up() {
        if (_held == null) return;
        _held = null;
        if (_moved) widget.onChangeEnd?.call();
        _moved = false;
      }

      final strip = Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                SizedBox(
                  height: PartStrip.filmHeight,
                  child: _Filmstrip(
                    frames: widget.thumbnails,
                    placeholder: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: PartStrip.gap),
                SizedBox(
                  height: PartStrip.levelHeight,
                  width: width,
                  child: CustomPaint(
                    painter: _LevelsPainter(
                      loudness: widget.loudness,
                      expected: (widget.durationMs / widget.bucketMs).ceil(),
                      bar: scheme.onSurfaceVariant,
                      track: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _WindowPainter(
                left: xOf(window.startMs),
                right: xOf(window.endMs),
                ink: scheme.onSurface,
                paper: scheme.surface,
              ),
            ),
          ),
        ],
      );

      return Semantics(
        label: widget.semanticLabel,
        onIncrease: () => _step(10000),
        onDecrease: () => _step(-10000),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Down, not start: the drag then counts from where the finger
          // landed, so the window stays under it after the touch slop.
          onHorizontalDragDown: (d) => down(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => move(d.localPosition.dx),
          onHorizontalDragEnd: (_) => up(),
          onHorizontalDragCancel: up,
          child: SizedBox(height: PartStrip.height, child: strip),
        ),
      );
    });
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.frames, required this.placeholder});

  final List<Uint8List?> frames;
  final Color placeholder;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(
        color: placeholder,
        child: Row(
          children: [
            for (final jpeg in frames)
              Expanded(
                child: jpeg == null
                    ? const SizedBox.expand()
                    : Image.memory(
                        jpeg,
                        fit: BoxFit.cover,
                        height: double.infinity,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LevelsPainter extends CustomPainter {
  _LevelsPainter({
    required this.loudness,
    required this.expected,
    required this.bar,
    required this.track,
  });

  final List<double> loudness;

  /// Buckets in the whole clip; the scan has read [loudness] of them.
  final int expected;
  final Color bar;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = track,
    );
    if (loudness.isEmpty || expected == 0) return;
    final readWidth = size.width * math.min(1.0, loudness.length / expected);
    final columns = math.max(1, (readWidth / 2).floor());
    final peaks = bucketMax(Float32List.fromList(loudness), columns);
    var high = 0.0;
    for (final p in peaks) {
      if (p > high) high = p;
    }
    if (high <= 0) return;
    final step = readWidth / columns;
    final paint = Paint()..color = bar;
    for (var i = 0; i < columns; i++) {
      final h = math.max(1.0, peaks[i] / high * (size.height - 4));
      canvas.drawRect(
        Rect.fromLTWH(
            i * step, size.height - 2 - h, math.max(1, step - 0.5), h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelsPainter old) =>
      old.loudness != loudness || old.bar != bar;
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({
    required this.left,
    required this.right,
    required this.ink,
    required this.paper,
  });

  final double left;
  final double right;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    // Outside the window is dimmed.
    final shade = Paint()..color = paper.withValues(alpha: 0.6);
    canvas.drawRect(Rect.fromLTRB(0, 0, left, size.height), shade);
    canvas.drawRect(Rect.fromLTRB(right, 0, size.width, size.height), shade);

    const w = PartStrip.handleWidth;
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, 0, right, size.height).deflate(1.5),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Handles: solid bars inside each end, with a grip line.
    final handle = Paint()..color = ink;
    final grip = Paint()
      ..color = paper
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (x0, x1) in [(left, left + w), (right - w, right)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, 0, x1, size.height),
          const Radius.circular(6),
        ),
        handle,
      );
      final mid = (x0 + x1) / 2;
      canvas.drawLine(Offset(mid, size.height / 2 - 8),
          Offset(mid, size.height / 2 + 8), grip);
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.left != left || old.right != right || old.ink != ink;
}
