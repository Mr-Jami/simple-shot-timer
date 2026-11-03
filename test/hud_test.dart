// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/services/video/export_plan.dart';
import 'package:simple_shot_timer/services/video/hud.dart';
import 'package:simple_shot_timer/services/video/hud_painter.dart';
import 'package:simple_shot_timer/widgets/video/hud_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // START at 10 s in the clip; shots 1.5, 2.0 and 2.6 s after it.
  final string = HudString(
    TimerString(
      createdAt: DateTime(2026, 10, 23),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [
        Shot(index: 0, timeMs: 1500),
        Shot(index: 1, timeMs: 2000),
        Shot(index: 2, timeMs: 2600),
      ],
      label: 'Bill drill',
      penaltyMs: 2000,
    ),
    startMs: 10000,
  );

  group('the overlay at a moment', () {
    test('the clock reads 0 before START, runs, and stops on the last shot',
        () {
      expect(HudMoment.at(string, 5000).clockMs, 0);
      expect(HudMoment.at(string, 11000).clockMs, 1000);
      expect(HudMoment.at(string, 30000).clockMs, 2600);
    });

    test('counts the shots fired, the one on the moment included', () {
      expect(HudMoment.at(string, 11499).fired, 0);
      expect(HudMoment.at(string, 11500).fired, 1);
      expect(HudMoment.at(string, 30000).fired, 3);
    });

    test('pulses the clock for 120 ms on each shot', () {
      expect(HudMoment.at(string, 11500).tick, 1);
      expect(HudMoment.at(string, 11560).tick, closeTo(1.06, 1e-9));
      expect(HudMoment.at(string, 11620).tick, 1);
    });

    test('fades the end card in half a second after the last shot', () {
      expect(HudMoment.at(string, 12600 + 500).endCard, 0);
      expect(HudMoment.at(string, 12600 + 650).endCard, closeTo(0.5, 1e-9));
      expect(HudMoment.at(string, 12600 + 800).endCard, 1);
      expect(HudMoment.at(string, 20000, endCard: false).endCard, 0);
    });

    test('fades the end card out 4 s after it came, past a string export', () {
      expect(HudMoment.at(string, 12600 + ExportPlan.tailMs).endCard, 1);
      expect(HudMoment.at(string, 12600 + 4500).endCard, 1);
      expect(HudMoment.at(string, 12600 + 4650).endCard, closeTo(0.5, 1e-9));
      expect(HudMoment.at(string, 12600 + 4800).endCard, 0);
      expect(HudMoment.at(string, 60000).endCard, 0);
    });

    test('splits run from START, then shot to shot', () {
      expect([for (var i = 0; i < 3; i++) string.splitMs(i)], [1500, 500, 600]);
    });
  });

  group('the layout', () {
    const landscape = Size(1920, 1080);
    const portrait = Size(1080, 1920);

    test('scales with the short side and keeps a margin', () {
      final l = HudLayout(landscape, const HudOptions());
      expect(l.unit, 54);
      expect(l.box.topLeft, Offset(0.8 * 54, 0.8 * 54));
      final r =
          HudLayout(landscape, const HudOptions(corner: HudCorner.bottomRight));
      expect(r.box.right, closeTo(1920 - 0.8 * 54, 1e-9));
      expect(r.box.bottom, closeTo(1080 - 0.8 * 54, 1e-9));
      expect(r.alignRight, isTrue);
    });

    test('every corner keeps the same margin, on 9:16 too', () {
      for (final frame in const [landscape, portrait]) {
        for (final corner in HudCorner.values) {
          final l = HudLayout(frame, HudOptions(corner: corner));
          final box = l.box;
          expect(l.alignRight ? frame.width - box.right : box.left,
              closeTo(0.8 * 54, 1e-9),
              reason: '$frame $corner');
          expect(l.alignBottom ? frame.height - box.bottom : box.top,
              closeTo(0.8 * 54, 1e-9),
              reason: '$frame $corner');
        }
      }
    });

    test('9:16 keeps the end card out of the bottom fifth', () {
      final l =
          HudLayout(portrait, const HudOptions(corner: HudCorner.bottomRight));
      expect(l.card.bottom, lessThanOrEqualTo(1920 * 4 / 5));
    });

    test('the end card never covers the corner overlay', () {
      for (final frame in const [landscape, portrait, Size(480, 854)]) {
        for (final corner in HudCorner.values) {
          final l = HudLayout(frame, HudOptions(corner: corner));
          expect(l.card.overlaps(l.box), isFalse, reason: '$frame $corner');
        }
      }
    });

    test('more style, taller box; the end card in the middle', () {
      double height(HudStyle s) =>
          HudLayout(landscape, HudOptions(style: s)).box.height;
      expect(height(HudStyle.clock), lessThan(height(HudStyle.splits)));
      expect(height(HudStyle.splits), lessThan(height(HudStyle.full)));
      final card = HudLayout(landscape, const HudOptions()).card;
      expect(card.center.dx, closeTo(960, 1e-9));
      expect(card.center.dy, closeTo(540, 1e-9));
    });
  });

  const labels = HudLabels(
    total: 'TOTAL',
    first: 'FIRST',
    average: 'AVERAGE',
    fastest: 'FASTEST',
    shots: 'SHOTS',
    penaltyTemplate: 'Penalty: \u0000s',
    locale: 'en',
  );

  test('bottom corners mirror the top ones: the mark in the corner', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint());
    final logo = await recorder.endRecording().toImage(4, 4);
    // The mark, and the yellow rule beside the splits: 3 shots at 12.6 s.
    (Rect, Rect) marks(HudCorner corner) {
      final options = HudOptions(style: HudStyle.full, corner: corner);
      final canvas = TestRecordingCanvas();
      paintHudBox(canvas, HudLayout(const Size(1080, 1920), options), string,
          options, HudMoment.at(string, 12600), labels,
          logo: logo);
      Rect first(Symbol method, int argument) => canvas.invocations
          .firstWhere((i) => i.invocation.memberName == method)
          .invocation
          .positionalArguments[argument] as Rect;
      return (first(#drawImageRect, 2), first(#drawRect, 0));
    }

    final box = HudLayout(
            const Size(1080, 1920), const HudOptions(style: HudStyle.full))
        .box;
    final (topMark, topRule) = marks(HudCorner.topLeft);
    final (bottomMark, bottomRule) = marks(HudCorner.bottomLeft);
    final (rightMark, rightRule) = marks(HudCorner.topRight);
    expect(topMark.topLeft, Offset.zero);
    expect(bottomMark.bottom, closeTo(box.height, 1e-9));
    for (final (top, bottom) in [
      (topMark, bottomMark),
      (topRule, bottomRule)
    ]) {
      expect(bottom.left, top.left);
      expect(bottom.top, closeTo(box.height - top.bottom, 1e-9));
    }
    // Right corners mirror sideways: the mark and the rule at the right.
    expect(rightMark.right, closeTo(box.width, 1e-9));
    expect(rightRule.right, closeTo(box.width, 1e-9));
    expect(rightRule.left, closeTo(box.width - topRule.right, 1e-9));
  });

  testWidgets('the preview draws the export\'s shadows, only smaller',
      (tester) async {
    // The export draws the box at its size; the preview draws the same box
    // scaled down. Shadows that blur in screen pixels would cover far more
    // of the small one.
    const options = HudOptions();
    final layout = HudLayout(const Size(1080, 1920), options);
    final m = HudMoment.at(string, 12600);
    Future<int> covered(double scale) async {
      final bleed = 2 * layout.unit;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(scale)
        ..translate(bleed, bleed);
      paintHudBox(canvas, layout, string, options, m, labels);
      final image = await recorder.endRecording().toImage(
          ((layout.box.width + 2 * bleed) * scale).ceil(),
          ((layout.box.height + 2 * bleed) * scale).ceil());
      final rgba = (await image.toByteData())!;
      var n = 0;
      for (var i = 3; i < rgba.lengthInBytes; i += 4) {
        if (rgba.getUint8(i) > 8) n++;
      }
      return n;
    }

    final (export, preview) = (await tester
        .runAsync(() async => (await covered(1), await covered(0.25))))!;
    // About 1 when the shadows scale; 1.46 with TextStyle.shadows.
    expect(preview / (export / 16), inInclusiveRange(0.85, 1.15));
  });

  test('the shade sits in the overlay\'s corner and the card in its own', () {
    const frame = Size(1080, 1920);
    for (final corner in HudCorner.values) {
      final l = HudLayout(frame, HudOptions(corner: corner));
      final right =
          corner == HudCorner.topRight || corner == HudCorner.bottomRight;
      final bottom =
          corner == HudCorner.bottomLeft || corner == HudCorner.bottomRight;
      expect(
          l.shadeCentre,
          Offset(right ? l.box.right : l.box.left,
              bottom ? l.box.bottom : l.box.top),
          reason: '$corner');
      expect(l.shade.contains(l.box.center), isTrue);
      expect((Offset.zero & frame).intersect(l.shade), l.shade);
      expect(l.cardShade.contains(l.card.topLeft), isTrue);
      expect(l.cardShade.contains(l.card.bottomRight - const Offset(1, 1)),
          isTrue);
    }
  });

  test('paints every style, corner and the end card without errors', () async {
    // The app's localizations load this; the end card's date needs it.
    await initializeDateFormatting('en');
    expect(labels.penalty(2000), 'Penalty: 2.00s');
    for (final frame in const [Size(1920, 1080), Size(1080, 1920)]) {
      for (final style in HudStyle.values) {
        for (final corner in HudCorner.values) {
          final options = HudOptions(style: style, corner: corner);
          final layout = HudLayout(frame, options);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          paintHudBox(canvas, layout, string, options,
              HudMoment.at(string, 12100), labels);
          paintEndCard(canvas, layout, string, labels);
          recorder.endRecording().dispose();
        }
      }
    }
  });

  test('the still parts and then the clock paint the same as all of it',
      () async {
    const frame = Size(360, 640);
    Future<Uint8List> pixels(HudLayout layout, void Function(Canvas) paint) =>
        _pixels(
          (layout.box.width + 2 * layout.unit).ceil(),
          (layout.box.height + 2 * layout.unit).ceil(),
          (canvas) => paint(canvas..translate(layout.unit, layout.unit)),
        );
    // Before START, the first shot's tick, and stopped on the last shot.
    for (final ms in const [9000, 11550, 12700]) {
      final m = HudMoment.at(string, ms);
      for (final style in HudStyle.values) {
        for (final corner in HudCorner.values) {
          final options = HudOptions(style: style, corner: corner);
          final layout = HudLayout(frame, options);
          void box(Canvas c, HudParts parts) =>
              paintHudBox(c, layout, string, options, m, labels, parts: parts);
          final all = await pixels(layout, (c) => box(c, HudParts.all));
          final parts = await pixels(layout, (c) {
            box(c, HudParts.still);
            box(c, HudParts.clock);
          });
          expect(_differing(parts, all), 0, reason: '$style $corner $ms ms');
        }
      }
    }
  });

  testWidgets(
      'the preview lays out only the clock as it runs, and the rest again '
      'when a shot fires', (tester) async {
    const frame = Size(360, 640);
    final time = ValueNotifier(11000);
    addTearDown(time.dispose);
    Widget overlay() => Center(
          child: SizedBox.fromSize(
            size: frame,
            child: HudOverlay(
              frame: frame,
              string: string,
              options: const HudOptions(),
              labels: labels,
              timeMs: () => time.value,
              repaint: time,
            ),
          ),
        );
    final boundary = find.descendant(
        of: find.byType(HudOverlay), matching: find.byType(RepaintBoundary));
    Future<Uint8List> shown() async => (await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(boundary)
              .toImage();
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          image.dispose();
          return bytes;
        }))!;

    await tester.pumpWidget(overlay());
    time.value = 11100;
    await tester.pump();
    // Only the clock's digits: two soft shadows, then the digits.
    expect(
      tester.renderObject(find.descendant(
          of: find.byType(HudOverlay), matching: find.byType(CustomPaint))),
      paintsExactlyCountTimes(#drawParagraph, 3),
    );

    // Two shots later it shows what a fresh overlay would.
    time.value = 12300;
    await tester.pump();
    final ran = await shown();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(overlay());
    expect(_differing(ran, await shown()), 0);
  });
}

/// What [paint] draws on a [width] x [height] canvas, in RGBA.
Future<Uint8List> _pixels(
    int width, int height, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

/// How many bytes of [a] and [b] differ (all of them in size).
int _differing(Uint8List a, Uint8List b) {
  if (a.length != b.length) return math.max(a.length, b.length);
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}
