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

    group('keeping clear of the apps\' buttons', () {
      HudLayout clear(Size frame, HudCorner corner,
              [HudStyle style = HudStyle.splits]) =>
          HudLayout(frame,
              HudOptions(style: style, corner: corner, clearOfButtons: true));

      test(
          'on 9:16 every corner is below the header, above the caption and '
          'beside the buttons', () {
        for (final style in HudStyle.values) {
          for (final corner in HudCorner.values) {
            final l = clear(portrait, corner, style);
            final reason = '$style $corner ${l.box}';
            // 13 % and 20 % of 1920, 15 % of 1080, the margin of 0.8 units.
            expect(l.box.top, greaterThanOrEqualTo(249.6 - 1e-9),
                reason: reason);
            expect(l.box.bottom, lessThanOrEqualTo(1536 + 1e-9),
                reason: reason);
            expect(l.box.right, lessThanOrEqualTo(918 + 1e-9), reason: reason);
            expect(l.box.left, greaterThanOrEqualTo(43.2 - 1e-9),
                reason: reason);
          }
        }
        // And in its corner of that room, not just anywhere inside it.
        final l = clear(portrait, HudCorner.topLeft);
        expect(l.box.left, closeTo(43.2, 1e-9));
        expect(l.box.top, closeTo(249.6, 1e-9));
        final r = clear(portrait, HudCorner.bottomRight);
        expect(r.box.bottomRight.dx, closeTo(918, 1e-9));
        expect(r.box.bottomRight.dy, closeTo(1536, 1e-9));
        expect((r.alignRight, r.alignBottom), (true, true));
      });

      test('a frame taller than 9:16 counts from its middle 9:16', () {
        // 1080 x 2340: 210 px above and below a 1080 x 1920 middle.
        const frame = Size(1080, 2340);
        expect(clear(frame, HudCorner.topRight).box.top,
            closeTo(210 + 249.6, 1e-9));
        expect(clear(frame, HudCorner.bottomLeft).box.bottom,
            closeTo(2340 - 210 - 384, 1e-9));
      });

      test('a tall frame wider than 9:16 counts from its whole height', () {
        const frame = Size(1080, 1728);
        expect(clear(frame, HudCorner.topLeft).box.top,
            closeTo(0.13 * 1728, 1e-9));
        final r = clear(frame, HudCorner.bottomRight);
        expect(r.box.bottom, closeTo(0.8 * 1728, 1e-9));
        expect(r.box.right, closeTo(918, 1e-9));
      });

      test('frames that are not tall stay as they are', () {
        for (final frame in const [
          landscape,
          Size(1080, 1080),
          Size(1080, 1440)
        ]) {
          for (final corner in HudCorner.values) {
            final usual = HudLayout(frame, HudOptions(corner: corner));
            final l = clear(frame, corner);
            expect(
                (l.box, l.card, l.shade), (usual.box, usual.card, usual.shade),
                reason: '$frame $corner');
          }
        }
      });

      test('off, a tall frame stays as it is', () {
        final l = HudLayout(portrait, const HudOptions());
        expect(l.box.topLeft, const Offset(43.2, 43.2));
      });

      test('the end card keeps the margin from the corner overlay', () {
        for (final frame in const [
          portrait,
          Size(480, 854),
          Size(1080, 1728),
          Size(1080, 2340),
        ]) {
          // The margin of 0.8 units, less a hair for the arithmetic.
          final margin = 0.8 * frame.width / 20 - 1e-6;
          for (final style in HudStyle.values) {
            for (final corner in HudCorner.values) {
              final l = clear(frame, corner, style);
              final reason = '$frame $style $corner ${l.card} ${l.box}';
              expect(l.card.inflate(margin).overlaps(l.box), isFalse,
                  reason: reason);
              expect(l.card.top, greaterThanOrEqualTo(0), reason: reason);
              expect(l.card.bottom, lessThanOrEqualTo(frame.height * 4 / 5),
                  reason: reason);
            }
          }
        }
      });

      test('9:16, Full, a bottom corner: the card moves up, above the box', () {
        // In the middle it would end 5 px above the box, its shade on the
        // box's top row.
        final l = clear(portrait, HudCorner.bottomLeft, HudStyle.full);
        expect(l.box.top - l.card.bottom, closeTo(43.2, 1e-9));
        expect(l.card.top, greaterThan(249.6));
        // Splits leaves the card room in the middle.
        final s = clear(portrait, HudCorner.bottomLeft);
        expect(s.card.center.dy, closeTo(1920 * 4 / 5 / 2, 1e-9));
      });

      test('off, the card moves only where it would cover the overlay', () {
        // 9:16, Splits, top left: 11 px under the box, as it always was.
        final l = HudLayout(portrait, const HudOptions());
        expect(l.card.center.dy, closeTo(1920 * 4 / 5 / 2, 1e-9));
        expect(l.card.top - l.box.bottom, inInclusiveRange(0, 43.2));
      });

      test('the shade goes with the overlay, inside the frame', () {
        for (final corner in HudCorner.values) {
          final l = clear(portrait, corner);
          expect(
              l.shadeCentre,
              Offset(l.alignRight ? l.box.right : l.box.left,
                  l.alignBottom ? l.box.bottom : l.box.top),
              reason: '$corner');
          expect((Offset.zero & portrait).intersect(l.shade), l.shade);
        }
      });
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
    final time = ValueNotifier(11000);
    addTearDown(time.dispose);
    Widget overlay() =>
        _preview(string, const HudOptions(), labels, () => time.value,
            repaint: time);
    final painter = find.descendant(
        of: find.byType(HudOverlay), matching: find.byType(CustomPaint));
    // The picture of the still parts: the first one it draws.
    ui.Picture still() {
      ui.Picture? drawn;
      expect(
        tester.renderObject(painter),
        paints
          ..something((method, args) {
            if (method != #drawPicture) return false;
            drawn = args.single as ui.Picture;
            return true;
          }),
      );
      return drawn!;
    }

    await tester.pumpWidget(overlay());
    final first = still();
    time.value = 11100;
    await tester.pump();
    // The same picture, and only the clock's digits laid out: two soft
    // shadows, then the digits.
    expect(still(), same(first));
    expect(tester.renderObject(painter),
        paintsExactlyCountTimes(#drawParagraph, 3));

    // A shot fires: a new picture. Two shots in, it shows what a fresh
    // overlay would.
    time.value = 11600;
    await tester.pump();
    expect(still(), isNot(same(first)));
    time.value = 12300;
    await tester.pump();
    final ran = await _shown(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(overlay());
    expect(_differing(ran, await _shown(tester)), 0);
  });

  testWidgets(
      'a rebuilt preview shows a new corner, style, shot or penalty at once',
      (tester) async {
    // The last shot 10 s later, so its split gets wider: the test font
    // draws every digit alike. At 24 s all three have fired either way, and
    // only the moved string's end card is up, where a penalty shows.
    final moved = HudString(
      string.string.copyWith(shots: [
        Shot(index: 0, timeMs: 1500),
        Shot(index: 1, timeMs: 2000),
        Shot(index: 2, timeMs: 12600),
      ]),
      startMs: string.startMs,
    );
    Widget overlay(HudOptions options, HudString shown) =>
        _preview(shown, options, labels, () => 24000);
    Future<Uint8List> fresh(Widget overlay) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(overlay);
      return _shown(tester);
    }

    final penalized = HudString(moved.string.copyWith(penaltyMs: 10000),
        startMs: moved.startMs);
    const corner = HudOptions(corner: HudCorner.bottomRight);
    const full =
        HudOptions(style: HudStyle.full, corner: HudCorner.bottomRight);
    var before = await fresh(overlay(const HudOptions(), string));
    for (final (change, next) in [
      ('corner', overlay(corner, string)),
      ('style', overlay(full, string)),
      ('shot', overlay(full, moved)),
      ('penalty', overlay(full, penalized)),
    ]) {
      await tester.pumpWidget(next);
      final rebuilt = await _shown(tester);
      final expected = await fresh(next);
      expect(_differing(expected, before), isNonZero, reason: change);
      expect(_differing(rebuilt, expected), 0, reason: change);
      before = expected;
    }
  });
}

/// The overlay over a 360 x 640 clip, in a box that size.
Widget _preview(HudString string, HudOptions options, HudLabels labels,
    int Function() timeMs,
    {Listenable? repaint}) {
  const frame = Size(360, 640);
  return Center(
    child: SizedBox.fromSize(
      size: frame,
      child: HudOverlay(
        frame: frame,
        string: string,
        options: options,
        labels: labels,
        timeMs: timeMs,
        repaint: repaint,
      ),
    ),
  );
}

/// What the overlay on screen shows, in RGBA.
Future<Uint8List> _shown(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(find.descendant(
              of: find.byType(HudOverlay),
              matching: find.byType(RepaintBoundary)))
          .toImage();
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;

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
