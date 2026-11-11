// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/widgets/repeat_button.dart';
import 'package:simple_shot_timer/widgets/timeline/shot_timeline.dart';
import 'package:simple_shot_timer/widgets/timeline/timeline_controller.dart';

void main() {
  // 10 s of frames, quiet but for one loud frame at 6 s.
  const frameMs = 1000 / 375;
  final quiet = Float32List(3750);
  final spike = Float32List(3750)..[(6000 / frameMs).floor()] = 1;

  late TimelineController controller;
  late List<TimelineMarker> tapped;
  late List<int> settled;

  Future<void> pumpTimeline(
    WidgetTester tester, {
    bool fling = true,
    List<TimelineMarker> markers = const [],
    TargetPlatform platform = TargetPlatform.android,
    Float32List? loudness,
    int originMs = 0,
  }) async {
    tapped = [];
    settled = [];
    controller = TimelineController(
      vsync: tester,
      endMs: 10000,
      platform: platform,
      pxPerSecond: 150,
      onSettle: settled.add,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: ShotTimeline(
              controller: controller,
              loudness: loudness ?? quiet,
              originMs: originMs,
              frameMs: frameMs,
              markers: markers,
              startLabel: 'START',
              carryingShot: !fling,
              onTouch: () {},
              onRelease: () {},
              onTapMarker: tapped.add,
              onTapEmpty: () {},
            ),
          ),
        ),
      ),
    ));
    controller.centreOn(5000, animate: false);
  }

  Offset centre(WidgetTester tester) =>
      tester.getCenter(find.byType(ShotTimeline));

  testWidgets("a long clip's part: its frames start at its own time",
      (tester) async {
    // Frames from 2 s on: the loud frame 1500 is at 6 s in the clip.
    final late = Float32List(3750)..[(4000 / frameMs).floor()] = 1;
    await pumpTimeline(tester, loudness: late, originMs: 2000);
    controller.centreOn(6000, animate: false);
    await tester.pump();
    expect(
      find.descendant(
          of: find.byType(ShotTimeline), matching: find.byType(CustomPaint)),
      paints
        ..clipRect(rect: const Rect.fromLTRB(-400, 38, 1100, 122))
        ..path(
          includes: const [Offset(200, 44), Offset(200, 116)],
          excludes: const [Offset(300, 76)],
        ),
    );
  });

  testWidgets('draws the loudness: a tall spike at the shot, flat in quiet',
      (tester) async {
    await pumpTimeline(tester, loudness: spike);
    controller.centreOn(6000, animate: false);
    await tester.pump();
    // The band is 84 px from y 38: middle 80, 40 px either way. The spike
    // sits under the playhead (x 200); 100 px on is quiet.
    expect(
      find.descendant(
          of: find.byType(ShotTimeline), matching: find.byType(CustomPaint)),
      paints
        // Only where the clip has frames: 0 to 10 s.
        ..clipRect(rect: const Rect.fromLTRB(-700, 38, 800, 122))
        ..path(
          includes: const [Offset(200, 44), Offset(200, 116)],
          excludes: const [Offset(300, 76), Offset(300, 84)],
        ),
    );
  });

  testWidgets('the playhead is two pointers, with no line over the waveform',
      (tester) async {
    await pumpTimeline(tester, loudness: spike, markers: const [
      TimelineMarker(ms: 4400, kind: TimelineMarkerKind.start),
      // Under the playhead (x 200), and 150 px right of it.
      TimelineMarker(
          ms: 5000,
          kind: TimelineMarkerKind.shot,
          id: 1,
          ordinal: 1,
          selected: true),
      TimelineMarker(
          ms: 6000, kind: TimelineMarkerKind.shot, id: 2, ordinal: 2),
    ]);
    await tester.pump();
    final timeline = find.descendant(
        of: find.byType(ShotTimeline), matching: find.byType(CustomPaint));
    expect(
      timeline,
      paints
        // The waveform first.
        ..path()
        // Above the band (y 38 to 122) pointing down, below it pointing up:
        // the tips touch the band's edges and stay out of the waveform.
        ..path(
          includes: const [Offset(200, 30), Offset(195, 30), Offset(200, 37)],
          excludes: const [Offset(200, 39), Offset(195, 37), Offset(200, 27)],
        )
        ..path(
          includes: const [
            Offset(200, 130),
            Offset(205, 130),
            Offset(200, 123)
          ],
          excludes: const [
            Offset(200, 121),
            Offset(205, 123),
            Offset(200, 133)
          ],
        ),
    );
    final lines = <(Offset, Offset)>[];
    expect(
      timeline,
      paints
        ..everything((method, arguments) {
          if (method == #drawLine) {
            lines.add((arguments[0] as Offset, arguments[1] as Offset));
          }
          return true;
        }),
    );
    // START and the other shot keep their lines down the band; nothing is
    // drawn down the playhead, not even the selected shot's line.
    expect(lines.map((l) => l.$1.dx), unorderedEquals([110.0, 350.0]));
    for (final (from, to) in lines) {
      expect(from.dx, to.dx);
      // From under the badges, through the room for the pointers.
      expect((from.dy, to.dy), (28, 122));
    }
  });

  testWidgets('a drag moves the clip 1:1 under the finger', (tester) async {
    await pumpTimeline(tester, fling: false);
    await tester.dragFrom(centre(tester), const Offset(-150, 0));
    await tester.pumpAndSettle();
    // 150 px at 150 px/s: one second later in the clip.
    expect(controller.playheadMs, closeTo(6000, 30));
  });

  testWidgets('a flick carries on; with a shot selected it stops',
      (tester) async {
    await pumpTimeline(tester);
    await tester.flingFrom(centre(tester), const Offset(-100, 0), 1500);
    await tester.pumpAndSettle();
    expect(controller.playheadMs, greaterThan(5000 + 100 / 150 * 1000 + 300));
    expect(settled, isNotEmpty);

    await pumpTimeline(tester, fling: false);
    await tester.flingFrom(centre(tester), const Offset(-100, 0), 1500);
    await tester.pumpAndSettle();
    expect(controller.playheadMs, closeTo(5000 + 100 / 150 * 1000, 30));
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        'pulled past the start it resists and springs back '
        '(${platform.name})', (tester) async {
      await pumpTimeline(tester, platform: platform);
      controller.centreOn(200, animate: false);
      final gesture = await tester.startGesture(centre(tester));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(280, 0));
      await tester.pump();
      // 300 px is 2000 ms of clip, but the band gives less.
      expect(controller.displayMs, lessThan(0));
      expect(controller.displayMs, greaterThan(200 - 2000));
      expect(controller.playheadMs, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.displayMs, closeTo(0, 1));
    });
  }

  testWidgets('a part of a long clip bounds the timeline', (tester) async {
    await pumpTimeline(tester);
    final part = TimelineController(
      vsync: tester,
      startMs: 60000,
      endMs: 240000,
      platform: TargetPlatform.android,
      pxPerSecond: 150,
    );
    addTearDown(part.dispose);
    part.centreOn(0, animate: false);
    expect(part.playheadMs, 60000);
    part.startDrag();
    part.dragTo(300);
    // Pulled before the part: it resists, and the video stays at its start.
    expect(part.displayMs, inExclusiveRange(58000, 60000));
    expect(part.playheadMs, 60000);
    part.endDrag(0);
    await tester.pumpAndSettle();
    expect(part.displayMs, closeTo(60000, 1));
    part.centreOn(999999, animate: false);
    expect(part.playheadMs, 240000);
  });

  testWidgets('a minimap scrub moves at once and settles when it ends',
      (tester) async {
    await pumpTimeline(tester);
    settled.clear();
    controller.scrubTo(2000);
    controller.scrubTo(2500);
    expect(controller.playheadMs, 2500);
    // The video follows with light seeks until the finger lifts.
    expect(settled, isEmpty);
    controller.endScrub();
    expect(settled, [2500]);
  });

  testWidgets('centring glides and lands exactly on the marker',
      (tester) async {
    await pumpTimeline(tester);
    controller.centreOn(6789);
    // A ticker's first frame is at zero elapsed time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.playheadMs, inExclusiveRange(5000, 6789));
    await tester.pumpAndSettle();
    expect(controller.playheadMs, closeTo(6789, 1e-6));
    expect(settled.last, 6789);
  });

  testWidgets('halting a flick stops it there and settles once',
      (tester) async {
    await pumpTimeline(tester);
    await tester.flingFrom(centre(tester), const Offset(-100, 0), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.motion, TimelineMotion.fling);
    settled.clear();
    final at = controller.playheadMs;
    controller.halt();
    expect(controller.motion, TimelineMotion.idle);
    expect(settled, [at.round()]);
    await tester.pumpAndSettle();
    expect(controller.playheadMs, at);
    expect(settled, hasLength(1));
  });

  testWidgets('halting a glide to a marker stops short of it', (tester) async {
    await pumpTimeline(tester);
    controller.centreOn(6789);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    settled.clear();
    final at = controller.playheadMs;
    expect(at, inExclusiveRange(5000, 6789));
    controller.halt();
    await tester.pumpAndSettle();
    expect(controller.playheadMs, at);
    expect(settled, [at.round()]);
  });

  testWidgets('halted while springing back from past an end, it lands on it',
      (tester) async {
    await pumpTimeline(tester);
    controller.centreOn(200, animate: false);
    controller.startDrag();
    controller.dragTo(300);
    controller.endDrag(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.displayMs, lessThan(0), reason: 'still stretched');
    settled.clear();
    controller.halt();
    expect(controller.displayMs, 0);
    expect(settled, [0]);
    await tester.pumpAndSettle();
    expect(settled, hasLength(1));
  });

  testWidgets('halting changes nothing at rest, under a finger or in playback',
      (tester) async {
    await pumpTimeline(tester);
    settled.clear();
    controller.halt();
    controller.follow(5200);
    controller.halt();
    expect(controller.motion, TimelineMotion.playback);
    controller.startDrag();
    controller.dragTo(-30);
    controller.halt();
    expect(controller.motion, TimelineMotion.drag);
    expect(settled, isEmpty);
    controller.endDrag(0);
  });

  testWidgets('pinching zooms around the fingers', (tester) async {
    await pumpTimeline(tester);
    controller.startDrag();
    final focalMs = controller.playheadMs + 100 / 150 * 1000;
    controller.zoom(4, 100);
    expect(controller.pxPerSecond, 600);
    expect(controller.playheadMs + 100 / 600 * 1000, closeTo(focalMs, 1e-6));
    controller.zoom(100, 0);
    expect(controller.pxPerSecond, 2000);
  });

  testWidgets('with a shot riding along, a pinch zooms around the playhead',
      (tester) async {
    Future<double> pinch(bool carrying) async {
      await pumpTimeline(tester, fling: !carrying);
      final at = controller.playheadMs;
      final c = centre(tester);
      // Two fingers right of the playhead, spreading apart.
      final a = await tester.startGesture(c + const Offset(60, 0));
      final b = await tester.startGesture(c + const Offset(140, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await a.moveBy(const Offset(-10, 0));
        await b.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(controller.pxPerSecond, greaterThan(150));
      return controller.playheadMs - at;
    }

    expect(await pinch(false), isNot(closeTo(0, 50)));
    expect(await pinch(true), closeTo(0, 1));
  });

  testWidgets('a tap picks the nearest marker', (tester) async {
    const near = TimelineMarker(ms: 5600, kind: TimelineMarkerKind.shot, id: 3);
    const far = TimelineMarker(ms: 7000, kind: TimelineMarkerKind.shot, id: 4);
    await pumpTimeline(tester, markers: const [near, far]);
    // 5600 ms is 90 px right of the playhead; tap 10 px off it.
    await tester.tapAt(centre(tester) + const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tapped.single.id, 3);
  });

  testWidgets('a nudge button steps once for a tap, a screen reader or a key',
      (tester) async {
    var steps = 0;
    var holds = 0;
    var ends = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepeatButton(
            icon: Icons.chevron_right,
            tooltip: 'later',
            onStart: () => holds++,
            onStep: () => steps++,
            onEnd: () => ends++,
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(RepeatButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect((steps, holds, ends), (1, 1, 1));
    // TalkBack, switch access and Enter all press the button itself.
    tester.widget<IconButton>(find.byType(IconButton)).onPressed!();
    expect((steps, holds, ends), (2, 2, 2));
  });

  testWidgets('holding a nudge button repeats, then speeds up', (tester) async {
    var steps = 0;
    var holds = 0;
    var ends = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepeatButton(
            icon: Icons.chevron_right,
            tooltip: 'later',
            onStart: () => holds++,
            onStep: () => steps++,
            onEnd: () => ends++,
          ),
        ),
      ),
    ));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(RepeatButton)));
    expect(steps, 1);
    await tester.pump(const Duration(milliseconds: 399));
    expect(steps, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(steps, 2);
    await tester.pump(const Duration(milliseconds: 1000));
    final afterOneSecond = steps;
    await tester.pump(const Duration(milliseconds: 400));
    // 40 ms apart now instead of 80.
    expect(steps - afterOneSecond, inInclusiveRange(9, 11));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(holds, 1);
    expect(ends, 1);
    final total = steps;
    await tester.pump(const Duration(seconds: 1));
    expect(steps, total);
  });
}
