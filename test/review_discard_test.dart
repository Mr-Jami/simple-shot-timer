// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/string_provider.dart';
import 'package:simple_shot_timer/screens/review_screen.dart';

/// Choose video again opens the editor over a string's Review. Discarding
/// the string there must not leave the user on a Review of nothing.
void main() {
  setUp(rootBundle.clear);

  testWidgets('a string deleted under its Review closes it', (tester) async {
    TimerString? stored = TimerString(
      id: 1,
      createdAt: DateTime(2026, 10, 23),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [Shot(index: 0, timeMs: 1500)],
      source: StringSource.video,
      videoStartMs: 1000,
    );
    final navigator = GlobalKey<NavigatorState>();
    final container = ProviderContainer(overrides: [
      stringByIdProvider.overrideWith((ref, id) async => stored),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Text('history')),
      ),
    ));
    // AppLocalizations reads its JSON from the asset bundle: real I/O.
    for (var i = 0; find.text('history').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ReviewScreen(stringId: 1)));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    // The editor, opened over it by Choose video again.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('editor'))));
    await tester.pumpAndSettle();

    // Discard deletes the string, then the editor closes.
    stored = null;
    container.invalidate(stringByIdProvider(1));
    await tester.pumpAndSettle();
    expect(find.text('editor'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen, skipOffstage: false), findsNothing);
    expect(find.text('history'), findsOneWidget);
  });
}
