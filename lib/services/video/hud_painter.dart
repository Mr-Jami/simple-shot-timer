// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../models/enums.dart';
import '../../utils/time_format.dart';
import 'hud.dart';

/// The brand yellow. The overlay always wears the brand, never the app's
/// monochrome theme.
const hudYellow = Color(0xFFFEE036);
const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _dimWhite = Color(0xB3FFFFFF);

/// The overlay's words in the app's language (`BuildContext.hudLabels`
/// makes them). The name stays English: it is the app's.
class HudLabels {
  const HudLabels({
    required this.total,
    required this.first,
    required this.average,
    required this.fastest,
    required this.shots,
    required this.penaltyTemplate,
    required this.locale,
  });

  /// Stands in for the seconds in [penaltyTemplate].
  static const placeholder = '\u0000';

  final String total;
  final String first;
  final String average;
  final String fastest;
  final String shots;

  /// "Penalty: …s", with [placeholder] for the seconds.
  final String penaltyTemplate;

  /// For the end card's date.
  final String locale;

  String penalty(int ms) =>
      penaltyTemplate.replaceFirst(placeholder, formatSeconds(ms));
}

// The look: white type with a soft shadow on a soft shade, no boxes, the
// brand yellow for the mark, the labels and one rule; like the stats on a
// sports app's share card.

/// The soft shade behind the corner overlay ([HudLayout.shade], in frame
/// coordinates): dark in the corner, gone further out, so white type reads
/// over bright footage too.
void paintHudShade(Canvas canvas, HudLayout layout) {
  canvas.drawRect(
    layout.shade,
    Paint()
      ..shader = ui.Gradient.radial(
        layout.shadeCentre,
        HudLayout.shadeUnits * layout.unit,
        // Eased out, so its edge never shows on a bright picture.
        [
          for (final alpha in const [0.7, 0.58, 0.38, 0.17, 0.05, 0.0])
            _black.withValues(alpha: alpha),
        ],
        const [0, 0.25, 0.5, 0.72, 0.88, 1],
      ),
  );
}

/// Paints the corner overlay into its box ([HudLayout.box], with the box's
/// top left at the canvas origin): the mark and name; the clock under the
/// TOTAL label (with the shot tick); for [HudStyle.full] the shots and the
/// first shot; and for every style but [HudStyle.clock] the newest splits
/// beside a yellow rule. The rows run from the corner out, so in bottom
/// corners they stack upwards and the mark sits in the corner there too.
void paintHudBox(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  HudOptions options,
  HudMoment m,
  HudLabels labels, {
  ui.Image? logo,
}) {
  final u = layout.unit;
  var fromCorner = 0.0;

  /// The top of the next row, [units] high.
  double row(double units) {
    final top = layout.alignBottom
        ? layout.box.height - fromCorner - units * u
        : fromCorner;
    fromCorner += units * u;
    return top;
  }

  _paintBrand(canvas, layout, logo, row(HudLayout.brandUnits));
  row(HudLayout.brandGapUnits);
  _paintClock(
    canvas,
    layout,
    labels,
    m,
    row(HudLayout.labelUnits + HudLayout.labelGapUnits + HudLayout.clockUnits),
  );
  if (options.style == HudStyle.full) {
    _paintLine(canvas, layout, s, m, labels, row(HudLayout.lineUnits));
  }
  final shown = math.min(m.fired, HudLayout.splits);
  if (options.style == HudStyle.clock || shown == 0) return;
  row(HudLayout.splitsGapUnits);
  // The newest next to the clock.
  final tops = [for (var i = 0; i < shown; i++) row(HudLayout.splitUnits)];
  final first = tops.reduce(math.min);
  final last = tops.reduce(math.max) + HudLayout.splitUnits * u;
  final ruleWidth = 0.08 * u;
  canvas.drawRect(
    Rect.fromLTRB(_x(layout, ruleWidth), first + 0.1 * u,
        _x(layout, ruleWidth) + ruleWidth, last - 0.1 * u),
    Paint()..color = hudYellow,
  );
  for (var age = 0; age < shown; age++) {
    _paintSplit(canvas, layout, s, m.fired - age, age, tops[age]);
  }
}

/// Paints the end card at [opacity] in frame coordinates, on a soft dark
/// field ([HudLayout.cardShade]): TOTAL large, then first, average, fastest
/// and shots, then the label, the date and any penalty, then the name.
void paintEndCard(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  HudLabels labels,
  double opacity, {
  ui.Image? logo,
}) {
  if (opacity <= 0) return;
  final u = layout.unit;
  final card = layout.card;
  canvas.saveLayer(
      layout.cardShade, Paint()..color = _white.withValues(alpha: opacity));
  canvas.drawRRect(
    RRect.fromRectAndRadius(card.inflate(0.6 * u), Radius.circular(1.2 * u)),
    Paint()
      ..color = _black.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, u),
  );
  final string = s.string;
  final cx = card.center.dx;
  final inner = card.width - 1.4 * u;
  _paintCentred(canvas, labels.total, cx, card.top + 0.2 * u, inner,
      _labelStyle(0.5 * u, hudYellow).copyWith(letterSpacing: 0.25 * u));
  _paintCentred(canvas, formatSeconds(string.totalTimeMs), cx,
      card.top + 0.95 * u, inner, _numberStyle(3.4 * u, u));

  // Four columns of smaller stats.
  String time(int? ms) => ms == null ? '–' : formatSeconds(ms);
  final stats = [
    (labels.first, time(string.firstShotMs)),
    (labels.average, time(string.averageSplitMs)),
    (labels.fastest, time(string.fastestSplitMs)),
    (labels.shots, '${string.shotCount}'),
  ];
  final column = card.width / stats.length;
  final top = card.top + 4.9 * u;
  for (final (i, (label, value)) in stats.indexed) {
    final centre = card.left + (i + 0.5) * column;
    _paintCentred(canvas, label, centre, top, column - 0.3 * u,
        _labelStyle(0.34 * u, _dimWhite));
    _paintCentred(canvas, value, centre, top + 0.55 * u, column - 0.3 * u,
        _numberStyle(0.95 * u, u));
    if (i > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
            card.left + i * column, top, math.max(1, 0.03 * u), 1.5 * u),
        Paint()..color = _white.withValues(alpha: 0.2),
      );
    }
  }

  final parts = [
    if (string.label?.isNotEmpty ?? false) string.label!,
    DateFormat.yMMMd(labels.locale).format(s.date),
    if (string.penaltyMs > 0) labels.penalty(string.penaltyMs),
  ];
  _paintCentred(canvas, parts.join('  ·  '), cx, card.top + 6.85 * u, inner,
      TextStyle(fontSize: 0.42 * u, color: _dimWhite, shadows: _soft(u)));

  // The mark and the name, centred at the foot.
  final mark = 0.5 * u;
  final name = _layout('SIMPLE SHOT TIMER', _nameStyle(0.34 * u, u));
  final gap = logo == null ? 0.0 : mark + 0.25 * u;
  final left = cx - (gap + name.width) / 2;
  final y = card.top + 7.6 * u;
  if (logo != null) {
    _paintMark(canvas, logo, Rect.fromLTWH(left, y, mark, mark));
  }
  name.paint(canvas, Offset(left + gap, y + (mark - name.height) / 2));
  name.dispose();
  canvas.restore();
}

// The box's rows, each at the top [y] paintHudBox gives it. [_x] places a
// row left or right.

/// Left in left corners, right in right corners.
double _x(HudLayout layout, double width) =>
    layout.alignRight ? layout.box.width - width : 0;

/// The mark in yellow and the name, the mark at the outer edge.
void _paintBrand(Canvas canvas, HudLayout layout, ui.Image? logo, double y) {
  final u = layout.unit;
  final mark = HudLayout.brandUnits * u;
  final name = _layout('SIMPLE SHOT TIMER', _nameStyle(0.46 * u, u));
  final gap = logo == null ? 0.0 : mark + 0.23 * u;
  final width = math.min(layout.box.width, gap + name.width);
  final x = _x(layout, width);
  if (logo != null) {
    final markX = layout.alignRight ? x + width - mark : x;
    _paintMark(canvas, logo, Rect.fromLTWH(markX, y, mark, mark));
  }
  final nameX = layout.alignRight ? x : x + gap;
  name.paint(canvas, Offset(nameX, y + (mark - name.height) / 2));
  name.dispose();
}

/// The TOTAL label, and under it the clock, pulsing on each shot around its
/// outer edge (the side the box hugs) at the baseline.
void _paintClock(
  Canvas canvas,
  HudLayout layout,
  HudLabels labels,
  HudMoment m,
  double y,
) {
  final u = layout.unit;
  final label = _layout(labels.total, _labelStyle(0.36 * u, hudYellow));
  label.paint(canvas, Offset(_x(layout, label.width), y));
  label.dispose();

  final size = HudLayout.clockUnits * u;
  final style = _numberStyle(size, u);
  final clock = formatSeconds(m.clockMs);
  final width = _textWidth(clock, style);
  // Big digits stand a little in from their box: align them with the label.
  final inset = 0.04 * size;
  final x =
      layout.alignRight ? _x(layout, width) + inset : _x(layout, width) - inset;
  final top = y + (HudLayout.labelUnits + HudLayout.labelGapUnits) * u;
  final pivot = Offset(layout.alignRight ? x + width : x, top + size);
  canvas
    ..save()
    ..translate(pivot.dx, pivot.dy)
    ..scale(m.tick)
    ..translate(-pivot.dx, -pivot.dy);
  final text = _layout(clock, style);
  text.paint(canvas, Offset(x, top));
  text.dispose();
  canvas.restore();
}

/// [HudStyle.full]'s line: shots so far and the first shot.
void _paintLine(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  HudMoment m,
  HudLabels labels,
  double y,
) {
  final u = layout.unit;
  final first = m.fired > 0 ? formatSeconds(s.string.shots.first.timeMs) : '–';
  final label = _labelStyle(0.34 * u, _dimWhite);
  final value = _numberStyle(0.62 * u, u);
  final line = TextPainter(
    text: TextSpan(children: [
      TextSpan(text: '${labels.shots}  ', style: label),
      TextSpan(text: '${m.fired}', style: value),
      TextSpan(text: '     ${labels.first}  ', style: label),
      TextSpan(text: first, style: value),
    ]),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  line.paint(canvas, Offset(_x(layout, line.width), y + 0.15 * u));
  line.dispose();
}

/// Shot [n]'s split, [age] shots old: the newest larger, older ones fading
/// from 90 to 60 %. Beside the rule: its number, then the split.
void _paintSplit(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  int n,
  int age,
  double y,
) {
  final u = layout.unit;
  final newest = age == 0;
  final opacity = newest ? 1.0 : 0.9 - 0.3 * (age - 1) / (HudLayout.splits - 2);
  final mid = y + HudLayout.splitUnits * u / 2;
  final number = _layout(
      '#$n', _labelStyle(0.38 * u, _white.withValues(alpha: 0.75 * opacity)));
  final split = _layout(
    formatSeconds(s.splitMs(n - 1)),
    _numberStyle(newest ? 0.8 * u : 0.64 * u, u)
        .copyWith(color: _white.withValues(alpha: opacity)),
  );
  final right = layout.alignRight;
  final w = layout.box.width;
  number.paint(
      canvas,
      Offset(right ? w - 0.42 * u - number.width : 0.42 * u,
          mid - number.height / 2));
  split.paint(
      canvas,
      Offset(right ? w - 1.45 * u - split.width : 1.45 * u,
          mid - split.height / 2));
  number.dispose();
  split.dispose();
}

void _paintMark(Canvas canvas, ui.Image logo, Rect at) => canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      at,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(hudYellow, BlendMode.srcIn),
    );

/// A soft shadow under white type, instead of an outline: readable over any
/// picture without looking stamped on.
List<Shadow> _soft(double u) => [
      Shadow(color: _black.withValues(alpha: 0.55), blurRadius: 0.35 * u),
      Shadow(color: _black.withValues(alpha: 0.35), blurRadius: 0.08 * u),
    ];

TextStyle _nameStyle(double size, double u) => TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      fontSize: size,
      color: _white,
      height: 1.0,
      letterSpacing: 0.04 * size,
      shadows: _soft(u),
    );

/// Small capitals, spaced out.
TextStyle _labelStyle(double size, Color color) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      height: 1.0,
      letterSpacing: 0.12 * size,
      shadows: [
        Shadow(color: _black.withValues(alpha: 0.6), blurRadius: 0.6 * size),
      ],
    );

TextStyle _numberStyle(double size, double u) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: _white,
      height: 1.0,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
      shadows: _soft(u),
    );

/// [text] laid out in [style]; with [maxWidth], shrunk to fit on one line.
TextPainter _layout(String text, TextStyle style, {double? maxWidth}) {
  TextPainter make(TextStyle s) => TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
  final painter = make(style);
  if (maxWidth == null || painter.width <= maxWidth) return painter;
  final size = style.fontSize! * maxWidth / painter.width;
  painter.dispose();
  return make(style.copyWith(
    fontSize: size,
    letterSpacing: style.letterSpacing == null
        ? null
        : style.letterSpacing! * size / style.fontSize!,
  ));
}

double _textWidth(String text, TextStyle style) {
  final p = _layout(text, style);
  final width = p.width;
  p.dispose();
  return width;
}

/// [text] centred on [centreX] at [y], at most [maxWidth] wide. Returns its
/// height.
double _paintCentred(
  Canvas canvas,
  String text,
  double centreX,
  double y,
  double maxWidth,
  TextStyle style,
) {
  final p = _layout(text, style, maxWidth: maxWidth);
  p.paint(canvas, Offset(centreX - p.width / 2, y));
  final height = p.height;
  p.dispose();
  return height;
}
