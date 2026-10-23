// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import '../../models/enums.dart';
import '../../models/timer_string.dart';

/// The video overlay's choices: what it shows, where, and whether the end
/// card follows the last shot.
class HudOptions {
  const HudOptions({
    this.style = HudStyle.splits,
    this.corner = HudCorner.topLeft,
    this.endCard = true,
  });

  final HudStyle style;
  final HudCorner corner;
  final bool endCard;

  @override
  bool operator ==(Object other) =>
      other is HudOptions &&
      other.style == style &&
      other.corner == corner &&
      other.endCard == endCard;

  @override
  int get hashCode => Object.hash(style, corner, endCard);
}

/// A string as the overlay tells it: [string]'s shots (times from START)
/// placed in a clip whose START is at [startMs].
class HudString {
  const HudString(this.string, {required this.startMs});

  final TimerString string;
  final int startMs;

  int get shotCount => string.shots.length;

  /// Shot [i] in clip time.
  int shotMs(int i) => startMs + string.shots[i].timeMs;

  /// The last shot in clip time: where the clock stops.
  int get endMs => shotCount == 0 ? startMs : shotMs(shotCount - 1);

  /// The split of shot [i]: from START for the first.
  int splitMs(int i) =>
      string.shots[i].timeMs - (i == 0 ? 0 : string.shots[i - 1].timeMs);

  /// When the string was shot: the recording date if the file says.
  DateTime get date => (string.videoRecordedAt ?? string.createdAt).toLocal();
}

/// What the overlay shows at one moment of the clip.
class HudMoment {
  const HudMoment({
    required this.clockMs,
    required this.fired,
    this.tick = 1,
    this.endCard = 0,
  });

  /// The shot tick: the clock grows by [tickGrowth] and back over 120 ms,
  /// the timing of the timer's big number (`kMotionTick`), twice its size
  /// because it is seen small, over a video.
  static const int tickMs = 120;
  static const double tickGrowth = 0.06;
  static const int endCardDelayMs = 500;
  static const int endCardFadeMs = 300;

  /// At clip time [ms]: the clock reads 0 before START, runs, and stops on
  /// the last shot; each shot pulses it for [tickMs] unless [pulse] is off
  /// (the preview under reduced motion); the end card fades in
  /// [endCardDelayMs] after the last shot.
  factory HudMoment.at(
    HudString s,
    int ms, {
    bool endCard = true,
    bool pulse = true,
  }) {
    var fired = 0;
    while (fired < s.shotCount && s.shotMs(fired) <= ms) {
      fired++;
    }
    var tick = 1.0;
    if (pulse && fired > 0) {
      final since = ms - s.shotMs(fired - 1);
      if (since < tickMs) {
        tick = 1 + tickGrowth * math.sin(math.pi * since / tickMs);
      }
    }
    var card = 0.0;
    if (endCard && s.shotCount > 0) {
      final shown = ms - s.endMs - endCardDelayMs;
      card = (shown / endCardFadeMs).clamp(0.0, 1.0).toDouble();
    }
    return HudMoment(
      clockMs: (ms.clamp(s.startMs, s.endMs) - s.startMs).toInt(),
      fired: fired,
      tick: tick,
      endCard: card,
    );
  }

  final int clockMs;

  /// Shots fired so far.
  final int fired;

  /// The clock's scale.
  final double tick;

  /// The end card's opacity, 0..1.
  final double endCard;
}

/// Where the overlay goes in a video frame of [frame] pixels (upright), in
/// units of the short side ÷ 20, so it looks the same at any resolution.
/// Tall frames (9:16) keep it out of the bottom fifth and away from the
/// right edge, where Reels, Shorts and TikTok draw their own buttons.
class HudLayout {
  factory HudLayout(Size frame, HudOptions options) {
    final unit = frame.shortestSide / 20;
    final tall = frame.height >= frame.width * 1.6;
    final margin = marginUnits * unit;
    final size = boxSize(unit, options.style);
    final right = options.corner == HudCorner.topRight ||
        options.corner == HudCorner.bottomRight;
    final bottom = options.corner == HudCorner.bottomLeft ||
        options.corner == HudCorner.bottomRight;
    final rightInset = margin + (tall ? frame.width * 0.15 : 0);
    final bottomInset = margin + (tall ? frame.height / 5 : 0);
    final left = right ? frame.width - rightInset - size.width : margin;
    final top = bottom ? frame.height - bottomInset - size.height : margin;

    // The end card in the middle; on tall frames, of the part above the
    // bottom fifth. Where that would cover the corner overlay (narrow
    // frames), it moves into the room beside it, above or below.
    final box = Rect.fromLTWH(left, top, size.width, size.height);
    final cardWidth = math.min(cardUnits.width * unit, frame.width * 0.9);
    final cardHeight = cardUnits.height * unit;
    final usable = tall ? frame.height * 4 / 5 : frame.height;
    var card = Rect.fromLTWH(
      (frame.width - cardWidth) / 2,
      (usable - cardHeight) / 2,
      cardWidth,
      cardHeight,
    );
    if (card.overlaps(box)) {
      final cardTop = bottom
          ? math.max(margin, box.top - margin - cardHeight)
          : math.min(box.bottom + margin, usable - margin - cardHeight);
      card = Rect.fromLTWH(card.left, cardTop, cardWidth, cardHeight);
    }
    return HudLayout._(
      frame: frame,
      unit: unit,
      box: box,
      card: card,
      alignRight: right,
    );
  }

  const HudLayout._({
    required this.frame,
    required this.unit,
    required this.box,
    required this.card,
    required this.alignRight,
  });

  // The box's rows, in units, top down: the badge, the clock, the Full
  // style's line, then five split chips.
  static const double marginUnits = 0.8;
  static const double widthUnits = 9;
  static const double badgeUnits = 1.2;
  static const double gapUnits = 0.3;
  static const double clockUnits = 2.8;
  static const double clockFontUnits = 2.4;
  static const double chipWidthUnits = 5.6;
  static const double lineUnits = 0.9;
  static const double chipUnits = 1.0;
  static const double chipPitchUnits = 1.2;
  static const int chips = 5;
  static const Size cardUnits = Size(13, 8.4);

  final Size frame;
  final double unit;

  /// The corner overlay: badge, clock, splits.
  final Rect box;

  /// The end card.
  final Rect card;

  /// Content hugs the box's right edge (right corners).
  final bool alignRight;

  static Size boxSize(double unit, HudStyle style) {
    var height = badgeUnits + gapUnits + clockUnits;
    if (style == HudStyle.full) height += lineUnits;
    if (style != HudStyle.clock) height += gapUnits + chips * chipPitchUnits;
    return Size(widthUnits * unit, height * unit);
  }
}
