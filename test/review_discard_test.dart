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
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/string_provider.dart';
import 'package:simple_shot_timer/screens/review_screen.dart';
import 'package:simple_shot_timer/services/database_service.dart';

import 'roboto.dart';

/// Records Review's own writes; nothing else is called.
class _MetaWrites implements DatabaseService {
  final writes = <({String? label, String? notes, int? penaltyMs})>[];

  @override
  Future<void> updateStringMeta(int id,
      {String? label, String? notes, int? penaltyMs}) async {
    writes.add((label: label, notes: notes, penaltyMs: penaltyMs));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Choose video again opens the editor over a string's Review. Whatever
/// happens to the string there (saved again, or discarded) must show in
/// the Review below once the editor closes.
void main() {
  // Roboto from the Flutter SDK: the test font's square glyphs overflow the
  // stats on a 360 dp screen.
  setUpAll(loadRoboto);

  setUp(rootBundle.clear);

  testWidgets('a string saved again under its Review shows what was saved',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    var stored = TimerString(
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
    final db = _MetaWrites();
    final navigator = GlobalKey<NavigatorState>();
    final container = ProviderContainer(overrides: [
      stringByIdProvider.overrideWith((ref, id) async => stored),
      databaseProvider.overrideWithValue(db),
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
    for (var i = 0; find.text('history').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ReviewScreen(stringId: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Penalty: 0.00s'), findsOneWidget);

    // The editor saves a label and 2 s of penalty, then closes.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('editor'))));
    await tester.pumpAndSettle();
    stored = stored.copyWith(label: 'Stage 3', penaltyMs: 2000);
    container.invalidate(stringByIdProvider(1));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Stage 3'), findsOneWidget);
    expect(find.text('Penalty: 2.00s'), findsOneWidget);
    await tester.tap(find.byTooltip('Add 1 s of penalty'));
    await tester.pumpAndSettle();
    expect(db.writes.last.label, 'Stage 3');
    expect(db.writes.last.penaltyMs, 3000);
  });

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
