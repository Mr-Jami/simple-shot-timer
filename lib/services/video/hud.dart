// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

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

  /// From the end card's first frame to its fade out: past the end of a
  /// string's export, so only the whole video shows it go.
  static const int endCardShowMs = 4000;

  /// At clip time [ms]: the clock reads 0 before START, runs, and stops on
  /// the last shot; each shot pulses it for [tickMs] unless [pulse] is off
  /// (the preview under reduced motion); the end card fades in
  /// [endCardDelayMs] after the last shot and out [endCardShowMs] later.
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
      card = (math.min(shown, endCardShowMs + endCardFadeMs - shown) /
              endCardFadeMs)
          .clamp(0.0, 1.0)
          .toDouble();
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
/// The corner overlay keeps the same margin in every corner. Tall frames
/// (9:16) keep the end card out of the bottom fifth, where Reels, Shorts
/// and TikTok draw their own captions.
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
    final left = right ? frame.width - margin - size.width : margin;
    final top = bottom ? frame.height - margin - size.height : margin;

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
    final whole = Offset.zero & frame;
    final corner =
        Offset(right ? box.right : box.left, bottom ? box.bottom : box.top);
    return HudLayout._(
      frame: frame,
      unit: unit,
      box: box,
      card: card,
      shadeCentre: corner,
      shade: Rect.fromCircle(center: corner, radius: shadeUnits * unit)
          .intersect(whole),
      cardShade: card.inflate(cardShadeUnits * unit).intersect(whole),
      alignRight: right,
      alignBottom: bottom,
    );
  }

  const HudLayout._({
    required this.frame,
    required this.unit,
    required this.box,
    required this.card,
    required this.shadeCentre,
    required this.shade,
    required this.cardShade,
    required this.alignRight,
    required this.alignBottom,
  });

  // In units: the box's margin and width, then its rows from the corner out
  // (the mark and name; the label over the clock; the Full style's line;
  // five splits), the corner's shade, then the end card and its shade.
  static const double marginUnits = 0.8;
  static const double widthUnits = 9;
  static const double brandUnits = 0.62;
  static const double brandGapUnits = 0.5;
  static const double labelUnits = 0.4;
  static const double labelGapUnits = 0.15;
  static const double clockUnits = 2.9;
  static const double lineUnits = 0.9;
  static const double splitsGapUnits = 0.35;
  static const double splitUnits = 0.82;
  static const int splits = 5;
  static const double shadeUnits = 13;
  static const Size cardUnits = Size(13, 8.4);
  static const double cardShadeUnits = 3.6;

  final Size frame;
  final double unit;

  /// The corner overlay: mark and name, clock, splits.
  final Rect box;

  /// The end card.
  final Rect card;

  /// The soft shade behind the corner overlay: dark at [shadeCentre], the
  /// box's corner in the frame's, gone [shadeUnits] away; [shade] holds it.
  final Offset shadeCentre;
  final Rect shade;

  /// The end card with the soft dark field around it.
  final Rect cardShade;

  /// Content hugs the box's right edge (right corners).
  final bool alignRight;

  /// Rows stack up from the box's bottom edge (bottom corners).
  final bool alignBottom;

  static Size boxSize(double unit, HudStyle style) {
    var height =
        brandUnits + brandGapUnits + labelUnits + labelGapUnits + clockUnits;
    if (style == HudStyle.full) height += lineUnits;
    if (style != HudStyle.clock) height += splitsGapUnits + splits * splitUnits;
    return Size(widthUnits * unit, height * unit);
  }
}
