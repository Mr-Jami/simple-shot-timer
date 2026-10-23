// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../i18n/app_localizations.dart';
import '../../models/enums.dart';
import '../../services/video/hud.dart';
import '../../utils/time_format.dart';

/// The brand yellow. The overlay always wears the brand, never the app's
/// monochrome theme.
const hudYellow = Color(0xFFFEE036);

/// The overlay's words in the app's language. The badge stays English: it
/// is the app's name.
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

  factory HudLabels.of(BuildContext context) => HudLabels(
        total: context.tr('review.summary.total'),
        first: context.tr('review.summary.first'),
        average: context.tr('review.summary.average'),
        fastest: context.tr('review.summary.fastest'),
        shots: context.tr('review.summary.shots'),
        penaltyTemplate:
            context.tr('review.penalty', args: {'seconds': _placeholder}),
        locale: context.dateLocale,
      );

  static const _placeholder = '\u0000';

  final String total;
  final String first;
  final String average;
  final String fastest;
  final String shots;

  /// "Penalty: …s", with a stand-in for the seconds.
  final String penaltyTemplate;

  /// For the end card's date.
  final String locale;

  String penalty(int ms) =>
      penaltyTemplate.replaceFirst(_placeholder, formatSeconds(ms));
}

/// Paints the corner overlay into its box ([HudLayout.box], with the box's
/// top left at the canvas origin): the badge, the clock (with the shot
/// tick), and for [HudStyle.full] and [HudStyle.splits] the newest splits.
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
  final width = layout.box.width;
  double x(double w) => layout.alignRight ? width - w : 0;

  // The badge: the mark and the name, black on yellow.
  final name = _layout('SIMPLE SHOT TIMER', _badgeStyle(u));
  const badgeH = HudLayout.badgeUnits;
  final markSize = badgeH * 0.72 * u;
  final pad = 0.3 * u;
  final badgeW = math.min(
    width,
    pad + (logo != null ? markSize + 0.2 * u : 0) + name.width + pad,
  );
  final bx = x(badgeW);
  canvas.drawRRect(
    RRect.fromLTRBR(bx, 0, bx + badgeW, badgeH * u, Radius.circular(0.25 * u)),
    Paint()..color = hudYellow,
  );
  var tx = bx + pad;
  if (logo != null) {
    canvas.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(tx, (badgeH * u - markSize) / 2, markSize, markSize),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );
    tx += markSize + 0.2 * u;
  }
  name.paint(canvas, Offset(tx, (badgeH * u - name.height) / 2));
  name.dispose();

  // The clock, pulsing on each shot around its leading edge.
  var y = (badgeH + HudLayout.gapUnits) * u;
  final clockSize = 2.4 * u;
  final clock = formatSeconds(m.clockMs);
  final clockW = _outlinedWidth(clock, _numberStyle(clockSize));
  final cx = x(clockW);
  canvas.save();
  final pivot = Offset(layout.alignRight ? cx + clockW : cx, y + clockSize);
  canvas
    ..translate(pivot.dx, pivot.dy)
    ..scale(m.tick)
    ..translate(-pivot.dx, -pivot.dy);
  _paintOutlined(canvas, clock, _numberStyle(clockSize), Offset(cx, y));
  canvas.restore();
  y += HudLayout.clockUnits * u;

  if (options.style == HudStyle.full) {
    final first = s.shotCount > 0 && m.fired > 0
        ? formatSeconds(s.string.shots.first.timeMs)
        : '–';
    final line = '${labels.shots} ${m.fired}   ${labels.first} $first';
    final style = _numberStyle(0.6 * u);
    _paintOutlined(
        canvas, line, style, Offset(x(_outlinedWidth(line, style)), y));
    y += HudLayout.lineUnits * u;
  }
  if (options.style == HudStyle.clock) return;

  // Splits, newest first: the newest on a yellow chip, older ones fading.
  y += HudLayout.gapUnits * u;
  const chipW = 5.6;
  for (var n = m.fired, age = 0; n >= 1 && age < HudLayout.chips; n--, age++) {
    final newest = age == 0;
    final opacity =
        newest ? 1.0 : 0.8 - 0.4 * (age - 1) / (HudLayout.chips - 2);
    final cx = x(chipW * u);
    canvas.drawRRect(
      RRect.fromLTRBR(cx, y, cx + chipW * u, y + HudLayout.chipUnits * u,
          Radius.circular(0.5 * u)),
      Paint()
        ..color =
            newest ? hudYellow : Colors.black.withValues(alpha: 0.55 * opacity),
    );
    final text = _layout(
      '#$n  ${formatSeconds(s.splitMs(n - 1))}',
      _numberStyle(0.62 * u).copyWith(
        color: newest ? Colors.black : Colors.white.withValues(alpha: opacity),
      ),
    );
    text.paint(canvas,
        Offset(cx + 0.35 * u, y + (HudLayout.chipUnits * u - text.height) / 2));
    text.dispose();
    y += HudLayout.chipPitchUnits * u;
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
  canvas.saveLayer(
      card, Paint()..color = Colors.white.withValues(alpha: opacity));
  canvas.drawRRect(
    RRect.fromRectAndRadius(card, Radius.circular(0.6 * u)),
    Paint()..color = Colors.black.withValues(alpha: 0.72),
  );
  final string = s.string;
  final pad = 0.7 * u;
  final inner = card.width - 2 * pad;
  var y = pad;

  void centred(String text, TextStyle style) {
    final p = _layout(text, style, maxWidth: inner);
    p.paint(canvas, Offset((card.width - p.width) / 2, y));
    y += p.height;
    p.dispose();
  }

  centred(
    labels.total,
    _numberStyle(0.6 * u).copyWith(color: hudYellow, letterSpacing: 0.15 * u),
  );
  centred(formatSeconds(string.totalTimeMs), _numberStyle(2.6 * u));
  y += 0.3 * u;

  // Four columns of smaller stats.
  final stats = [
    (labels.first, string.firstShotMs),
    (labels.average, string.averageSplitMs),
    (labels.fastest, string.fastestSplitMs),
  ];
  final column = inner / 4;
  for (var i = 0; i < 4; i++) {
    final (label, value) = i < 3
        ? (stats[i].$1, stats[i].$2 == null ? '–' : formatSeconds(stats[i].$2!))
        : (labels.shots, '${string.shotCount}');
    final left = pad + i * column;
    final l = _layout(
        label,
        _numberStyle(0.42 * u)
            .copyWith(color: Colors.white70, letterSpacing: 0.05 * u),
        maxWidth: column - 0.2 * u);
    l.paint(canvas, Offset(left + (column - l.width) / 2, y));
    final v =
        _layout(value, _numberStyle(0.95 * u), maxWidth: column - 0.2 * u);
    v.paint(canvas, Offset(left + (column - v.width) / 2, y + l.height));
    l.dispose();
    v.dispose();
  }
  y += 1.9 * u;

  final date = DateFormat.yMMMd(labels.locale).format(s.date);
  final parts = [
    if (string.label?.isNotEmpty ?? false) string.label!,
    date,
    if (string.penaltyMs > 0) labels.penalty(string.penaltyMs),
  ];
  centred(parts.join('  ·  '),
      const TextStyle().copyWith(fontSize: 0.5 * u, color: Colors.white70));
  canvas.restore();
}

TextStyle _badgeStyle(double u) => TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w800,
      fontStyle: FontStyle.italic,
      fontSize: 0.62 * u,
      color: Colors.black,
      letterSpacing: 0.02 * u,
    );

TextStyle _numberStyle(double size) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

/// [text] laid out in [style]; with [maxWidth], shrunk to fit on one line.
TextPainter _layout(String text, TextStyle style, {double? maxWidth}) {
  var painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  if (maxWidth != null && painter.width > maxWidth) {
    final size = style.fontSize! * maxWidth / painter.width;
    painter.dispose();
    painter = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }
  return painter;
}

double _outlinedWidth(String text, TextStyle style) {
  final p = _layout(text, style);
  final w = p.width;
  p.dispose();
  return w;
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
        ..color = Colors.black.withValues(alpha: 0.85),
    ),
  );
  outline.paint(canvas, at);
  outline.dispose();
  final fill = _layout(text, style);
  fill.paint(canvas, at);
  fill.dispose();
}
