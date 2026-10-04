// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/widgets/flash_overlay.dart';

Widget _host(int trigger, {bool reducedMotion = false}) => MaterialApp(
      home: FlashOverlay(
        trigger: trigger,
        reducedMotion: reducedMotion,
        child: const SizedBox.expand(),
      ),
    );

Finder _visibleSignal() => find.descendant(
      of: find.byType(FlashOverlay),
      matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity > 0),
    );

void main() {
  testWidgets('a higher trigger plays one pulse', (tester) async {
    await tester.pumpWidget(_host(3));
    expect(_visibleSignal(), findsNothing);

    await tester.pumpWidget(_host(4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_visibleSignal(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(_visibleSignal(), findsNothing);
  });

  testWidgets('a lower trigger (counter reset for a new run) does not flash',
      (tester) async {
    await tester.pumpWidget(_host(7));
    await tester.pumpWidget(_host(0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_visibleSignal(), findsNothing);
  });

  testWidgets('reduced motion draws an edge ring instead of a white fill',
      (tester) async {
    await tester.pumpWidget(_host(1, reducedMotion: true));
    await tester.pumpWidget(_host(2, reducedMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_visibleSignal(), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FlashOverlay),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(FlashOverlay),
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
    );
  });
}
