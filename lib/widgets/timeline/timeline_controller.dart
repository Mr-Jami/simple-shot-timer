// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../utils/timeline_math.dart';

/// What moves the playhead right now.
enum TimelineMotion { idle, playback, drag, fling, settle }

/// The playhead and zoom of the video editor's timeline. The playhead sits
/// still in the middle and the clip moves under it: a drag follows the
/// finger 1:1, a fling carries on with the platform's own physics (iOS
/// bounces at the ends, Android stops), a drag past an end resists and
/// springs back, and centring on a marker is a critically damped spring.
/// Touching the timeline stops whatever was moving.
///
/// [onUserMove] reports every move the user caused (to seek the video and
/// tick the haptics), [onSettle] where it came to rest (the exact seek).
class TimelineController extends ChangeNotifier {
  TimelineController({
    required TickerProvider vsync,
    required this.durationMs,
    required this.platform,
    double pxPerSecond = 150,
    this.onUserMove,
    this.onSettle,
  }) : _pxPerSecond = clampZoom(pxPerSecond) {
    _ticker = vsync.createTicker(_tick);
  }

  final int durationMs;
  final TargetPlatform platform;
  final void Function(double fromMs, double toMs)? onUserMove;
  final ValueChanged<int>? onSettle;

  late final Ticker _ticker;
  Simulation? _simulation;
  var _motion = TimelineMotion.idle;
  double _pxPerSecond;

  /// Playhead position in pixels at the current zoom; may sit past an end
  /// while the rubber band stretches.
  double _px = 0;
  double _dragStartPx = 0;
  double _zoomStartPps = 0;

  /// Width of the timeline, for the rubber band; set by its widget.
  double viewportWidth = 360;

  TimelineMotion get motion => _motion;
  double get pxPerSecond => _pxPerSecond;
  double get _maxPx => durationMs * _pxPerSecond / 1000;

  /// Where the timeline is drawn, past an end while stretching.
  double get displayMs => _px / _pxPerSecond * 1000;

  /// Where the video is: [displayMs] kept inside the clip.
  double get playheadMs => displayMs.clamp(0, durationMs.toDouble()).toDouble();

  bool get _bounces =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// Follows the video while it plays; ignored while the user moves it.
  void follow(int ms) {
    if (_motion == TimelineMotion.drag ||
        _motion == TimelineMotion.fling ||
        _motion == TimelineMotion.settle) {
      return;
    }
    _motion = TimelineMotion.playback;
    _setPx(ms * _pxPerSecond / 1000, user: false);
  }

  /// The video stopped: the playhead stays where it is.
  void stopFollowing() {
    if (_motion == TimelineMotion.playback) _motion = TimelineMotion.idle;
  }

  void startDrag() {
    _stop();
    _motion = TimelineMotion.drag;
    _dragStartPx = _px;
    _zoomStartPps = _pxPerSecond;
  }

  /// The finger is [dxPx] from where the drag started (right is positive,
  /// so the clip moves back). Absolute, so the clip stays glued to the
  /// point it was grabbed at.
  void dragTo(double dxPx) {
    if (_motion != TimelineMotion.drag) startDrag();
    final max = _maxPx;
    final raw = _dragStartPx - dxPx;
    final shown = raw < 0
        ? rubberBand(raw, viewportWidth)
        : raw > max
            ? max + rubberBand(raw - max, viewportWidth)
            : raw;
    _setPx(shown, user: true);
  }

  /// Pinch: [scale] since the gesture began, fingers [focalPx] from the
  /// playhead.
  void zoom(double scale, double focalPx) {
    if (_motion != TimelineMotion.drag) startDrag();
    final next = clampZoom(_zoomStartPps * scale);
    if (next == _pxPerSecond) return;
    final ms = zoomAround(
      playheadMs: playheadMs,
      focalPx: focalPx,
      oldPxPerSecond: _pxPerSecond,
      newPxPerSecond: next,
    ).clamp(0, durationMs.toDouble()).toDouble();
    final before = displayMs;
    _pxPerSecond = next;
    _px = ms * next / 1000;
    _dragStartPx = _px;
    onUserMove?.call(before, displayMs);
    notifyListeners();
  }

  /// The finger lifted at [velocityPxPerSecond]. With [fling] off (a shot is
  /// riding under the playhead) the timeline stops where it is.
  void endDrag(double velocityPxPerSecond, {bool fling = true}) {
    if (_motion != TimelineMotion.drag) return;
    final max = _maxPx;
    final v = -velocityPxPerSecond;
    if (_px < 0 || _px > max) {
      _run(_springTo(_px < 0 ? 0 : max, v), TimelineMotion.settle);
    } else if (fling && v.abs() > 50) {
      _run(
        _bounces
            ? BouncingScrollSimulation(
                position: _px,
                velocity: v,
                leadingExtent: 0,
                trailingExtent: max,
                spring: SpringDescription.withDampingRatio(
                  mass: 0.5,
                  stiffness: 100,
                  ratio: 1.1,
                ),
                tolerance: Tolerance.defaultTolerance,
              )
            : ClampingScrollSimulation(position: _px, velocity: v),
        TimelineMotion.fling,
      );
    } else {
      _settled();
    }
  }

  /// Brings [ms] under the playhead, gliding there unless [animate] is off
  /// (reduced motion) or it is already close.
  void centreOn(int ms, {bool animate = true}) {
    _stop();
    final target = ms.clamp(0, durationMs) * _pxPerSecond / 1000;
    if (!animate || (target - _px).abs() < 1) {
      _setPx(target, user: true);
      _settled();
      return;
    }
    _run(_springTo(target, 0), TimelineMotion.settle);
  }

  /// A critically damped spring: no overshoot, about a third of a second.
  Simulation _springTo(double px, double velocity) => SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: 1),
        _px,
        px,
        velocity,
        tolerance: const Tolerance(distance: 0.5, velocity: 5),
      );

  void _run(Simulation simulation, TimelineMotion motion) {
    _stop();
    _simulation = simulation;
    _motion = motion;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final simulation = _simulation;
    if (simulation == null) return;
    final t = elapsed.inMicroseconds / 1e6;
    var px = simulation.x(t);
    final done = simulation.isDone(t);
    final max = _maxPx;
    final clamping = !_bounces && _motion == TimelineMotion.fling;
    final hitEnd = clamping && (px <= 0 || px >= max);
    if (hitEnd) px = px.clamp(0, max).toDouble();
    _setPx(px, user: true);
    if (done || hitEnd) {
      _stop();
      _settled();
    }
  }

  void _setPx(double px, {required bool user}) {
    if (px == _px) return;
    final before = displayMs;
    _px = px;
    if (user) onUserMove?.call(before, displayMs);
    notifyListeners();
  }

  void _settled() {
    _motion = TimelineMotion.idle;
    onSettle?.call(playheadMs.round());
  }

  void _stop() {
    _ticker.stop();
    _simulation = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
