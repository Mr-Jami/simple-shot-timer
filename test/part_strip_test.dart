// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/part_window.dart';
import 'package:simple_shot_timer/widgets/part_strip.dart';

void main() {
  // Ten minutes over 400 px: 1.5 s per pixel. The window starts at 2:00
  // and ends at 4:00, so it spans x 80..160.
  const tenMinutes = 10 * 60 * 1000;
  late PartWindow window;
  late List<PartEdge> edges;
  late int ends;

  Future<Offset> pumpStrip(WidgetTester tester) async {
    window = const PartWindow(120000, 240000);
    edges = [];
    ends = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: StatefulBuilder(
              builder: (context, setState) => PartStrip(
                durationMs: tenMinutes,
                window: window,
                loudness: const [0.1, 0.4, 0.2],
                bucketMs: 250,
                thumbnails: List.filled(10, null),
                onChanged: (w, edge) => setState(() {
                  window = w;
                  edges.add(edge);
                }),
                onChangeEnd: () => ends++,
              ),
            ),
          ),
        ),
      ),
    ));
    return tester.getTopLeft(find.byType(PartStrip)) +
        const Offset(0, PartStrip.height / 2);
  }

  testWidgets('dragging inside moves the window with the finger',
      (tester) async {
    final left = await pumpStrip(tester);
    await tester.dragFrom(left + const Offset(120, 0), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(window, const PartWindow(210000, 330000));
    expect(edges.toSet(), {PartEdge.whole});
    expect(ends, 1);
  });

  testWidgets('dragging a handle moves only that edge', (tester) async {
    final left = await pumpStrip(tester);
    await tester.dragFrom(left + const Offset(87, 0), const Offset(-20, 0));
    await tester.pumpAndSettle();
    expect(window, const PartWindow(90000, 240000));
    expect(edges.last, PartEdge.start);

    await tester.dragFrom(left + const Offset(153, 0), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(window, const PartWindow(90000, 270000));
    expect(edges.last, PartEdge.end);
  });

  testWidgets('never grows past three minutes', (tester) async {
    final left = await pumpStrip(tester);
    await tester.dragFrom(left + const Offset(153, 0), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(window.lengthMs, maxClipPartMs);
    expect(window.startMs, 120000);
  });

  testWidgets('a tap outside centres the window there', (tester) async {
    final left = await pumpStrip(tester);
    await tester.tapAt(left + const Offset(300, 0));
    await tester.pumpAndSettle();
    // 300 px is 7:30; the two-minute window now runs 6:30 to 8:30.
    expect(window, const PartWindow(390000, 510000));
  });
}
