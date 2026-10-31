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
/// makes them). The badge stays English: it is the app's name.
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

/// Paints the corner overlay into its box ([HudLayout.box], with the box's
/// top left at the canvas origin): the badge, the clock (with the shot
/// tick), for [HudStyle.full] a line with the shots and the first shot,
/// and for every style but [HudStyle.clock] the newest splits. The rows
/// run from the corner out, so in bottom corners they stack upwards and
/// the badge sits in the corner there too.
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

  _paintBadge(canvas, layout, logo, row(HudLayout.badgeUnits));
  row(HudLayout.gapUnits);
  _paintClock(canvas, layout, m, row(HudLayout.clockUnits));
  if (options.style == HudStyle.full) {
    _paintLine(canvas, layout, s, m, labels, row(HudLayout.lineUnits));
  }
  if (options.style == HudStyle.clock) return;
  row(HudLayout.gapUnits);
  // The newest next to the clock.
  for (var n = m.fired, age = 0; n >= 1 && age < HudLayout.chips; n--, age++) {
    _paintSplit(canvas, layout, s, n, age, row(HudLayout.chipUnits));
    row(HudLayout.chipPitchUnits - HudLayout.chipUnits);
  }
}

/// Paints the end card into its box ([HudLayout.card], top left at the
/// canvas origin) at [opacity]: TOTAL large, then first, average, fastest
/// and shots, then the label, the date and any penalty.
void paintEndCard(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  HudLabels labels,
  double opacity,
) {
  if (opacity <= 0) return;
  final u = layout.unit;
  final card = Offset.zero & layout.card.size;
  canvas.saveLayer(card, Paint()..color = _white.withValues(alpha: opacity));
  canvas.drawRRect(
    RRect.fromRectAndRadius(card, Radius.circular(0.6 * u)),
    Paint()..color = _black.withValues(alpha: 0.72),
  );
  final string = s.string;
  final pad = 0.7 * u;
  final inner = card.width - 2 * pad;
  var y = pad;
  y += _paintCentred(
      canvas,
      labels.total,
      card.width / 2,
      y,
      inner,
      _numberStyle(0.6 * u)
          .copyWith(color: hudYellow, letterSpacing: 0.15 * u));
  y += _paintCentred(canvas, formatSeconds(string.totalTimeMs), card.width / 2,
      y, inner, _numberStyle(2.6 * u));
  y += 0.3 * u;

  // Four columns of smaller stats.
  String time(int? ms) => ms == null ? '–' : formatSeconds(ms);
  final stats = [
    (labels.first, time(string.firstShotMs)),
    (labels.average, time(string.averageSplitMs)),
    (labels.fastest, time(string.fastestSplitMs)),
    (labels.shots, '${string.shotCount}'),
  ];
  final column = inner / stats.length;
  for (final (i, (label, value)) in stats.indexed) {
    final centre = pad + (i + 0.5) * column;
    final labelStyle = _numberStyle(0.42 * u)
        .copyWith(color: _dimWhite, letterSpacing: 0.05 * u);
    final h =
        _paintCentred(canvas, label, centre, y, column - 0.2 * u, labelStyle);
    _paintCentred(
        canvas, value, centre, y + h, column - 0.2 * u, _numberStyle(0.95 * u));
  }
  y += 1.9 * u;

  final parts = [
    if (string.label?.isNotEmpty ?? false) string.label!,
    DateFormat.yMMMd(labels.locale).format(s.date),
    if (string.penaltyMs > 0) labels.penalty(string.penaltyMs),
  ];
  _paintCentred(canvas, parts.join('  ·  '), card.width / 2, y, inner,
      TextStyle(fontSize: 0.5 * u, color: _dimWhite));
  canvas.restore();
}

// The box's rows, each at the top [y] paintHudBox gives it. [_x] places a
// row left or right.

/// Left in left corners, right in right corners.
double _x(HudLayout layout, double width) =>
    layout.alignRight ? layout.box.width - width : 0;

/// The badge: the mark and the name, black on yellow.
void _paintBadge(Canvas canvas, HudLayout layout, ui.Image? logo, double y) {
  final u = layout.unit;
  const height = HudLayout.badgeUnits;
  final name = _layout('SIMPLE SHOT TIMER', _badgeStyle(u));
  final mark = height * 0.72 * u;
  final pad = 0.3 * u;
  final width = math.min(
    layout.box.width,
    pad + (logo != null ? mark + 0.2 * u : 0) + name.width + pad,
  );
  final x = _x(layout, width);
  canvas.drawRRect(
    RRect.fromLTRBR(x, y, x + width, y + height * u, Radius.circular(0.25 * u)),
    Paint()..color = hudYellow,
  );
  var tx = x + pad;
  if (logo != null) {
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(tx, y + (height * u - mark) / 2, mark, mark),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(_black, BlendMode.srcIn),
    );
    tx += mark + 0.2 * u;
  }
  name.paint(canvas, Offset(tx, y + (height * u - name.height) / 2));
  name.dispose();
}

/// The clock, pulsing on each shot around its outer edge (the side the box
/// hugs) at the baseline.
void _paintClock(Canvas canvas, HudLayout layout, HudMoment m, double y) {
  final u = layout.unit;
  final style = _numberStyle(HudLayout.clockFontUnits * u);
  final clock = formatSeconds(m.clockMs);
  final width = _textWidth(clock, style);
  final x = _x(layout, width);
  final pivot = Offset(layout.alignRight ? x + width : x, y + style.fontSize!);
  canvas
    ..save()
    ..translate(pivot.dx, pivot.dy)
    ..scale(m.tick)
    ..translate(-pivot.dx, -pivot.dy);
  _paintOutlined(canvas, clock, style, Offset(x, y));
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
  final first = m.fired > 0 ? formatSeconds(s.string.shots.first.timeMs) : '–';
  final line = '${labels.shots} ${m.fired}   ${labels.first} $first';
  final style = _numberStyle(0.6 * layout.unit);
  _paintOutlined(
      canvas, line, style, Offset(_x(layout, _textWidth(line, style)), y));
}

/// Shot [n]'s split, [age] shots old: the newest on a yellow chip, older
/// ones fading from 80 to 40 %.
void _paintSplit(
  Canvas canvas,
  HudLayout layout,
  HudString s,
  int n,
  int age,
  double y,
) {
  final u = layout.unit;
  final width = HudLayout.chipWidthUnits * u;
  const height = HudLayout.chipUnits;
  final x = _x(layout, width);
  final newest = age == 0;
  final opacity = newest ? 1.0 : 0.8 - 0.4 * (age - 1) / (HudLayout.chips - 2);
  canvas.drawRRect(
    RRect.fromLTRBR(x, y, x + width, y + height * u, Radius.circular(0.5 * u)),
    Paint()
      ..color = newest ? hudYellow : _black.withValues(alpha: 0.55 * opacity),
  );
  final text = _layout(
    '#$n  ${formatSeconds(s.splitMs(n - 1))}',
    _numberStyle(0.62 * u).copyWith(
      color: newest ? _black : _white.withValues(alpha: opacity),
    ),
  );
  text.paint(canvas, Offset(x + 0.35 * u, y + (height * u - text.height) / 2));
  text.dispose();
}

TextStyle _badgeStyle(double u) => TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      fontSize: 0.62 * u,
      color: _black,
      letterSpacing: 0.02 * u,
    );

TextStyle _numberStyle(double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: _white,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
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
  return make(style.copyWith(fontSize: size));
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

/// White text with a dark outline, readable over any picture.
void _paintOutlined(Canvas canvas, String text, TextStyle style, Offset at) {
  final outline = _layout(
    text,
    TextStyle(
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontFeatures: style.fontFeatures,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.fontSize! * 0.12
        ..strokeJoin = StrokeJoin.round
        ..color = _black.withValues(alpha: 0.85),
    ),
  );
  outline.paint(canvas, at);
  outline.dispose();
  final fill = _layout(text, style);
  fill.paint(canvas, at);
  fill.dispose();
}
