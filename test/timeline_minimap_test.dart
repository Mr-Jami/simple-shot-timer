// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/widgets/timeline/timeline_controller.dart';
import 'package:simple_shot_timer/widgets/timeline/timeline_minimap.dart';

void main() {
  testWidgets('draws the loudness on the same 0 to 1 scale as the timeline',
      (tester) async {
    final controller = TimelineController(
      vsync: tester,
      endMs: 10000,
      platform: TargetPlatform.android,
    );
    addTearDown(controller.dispose);
    // 10 s of frames at half loudness, one loud frame at 6 s.
    final loudness = Float32List(3750)
      ..fillRange(0, 3750, 0.5)
      ..[2250] = 1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: TimelineMinimap(
              controller: controller,
              loudness: loudness,
              originMs: 0,
              frameMs: 1000 / 375,
              markers: const [],
              onJump: (_) {},
              onScrub: (_) {},
              onScrubEnd: () {},
            ),
          ),
        ),
      ),
    ));
    final bars = <Rect>[];
    expect(
      find.descendant(
          of: find.byType(TimelineMinimap), matching: find.byType(CustomPaint)),
      paints
        ..everything((method, arguments) {
          if (method == #drawRect) bars.add(arguments.first as Rect);
          return true;
        }),
    );
    // 28 px high, 3 px margins: half loudness is 11 px, full 22 px.
    expect(bars, hasLength(400));
    expect(bars.first, const Rect.fromLTWH(0, 14, 1, 11));
    expect(bars[240], const Rect.fromLTWH(240, 3, 1, 22));
  });
}
