// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// ignore_for_file: depend_on_referenced_packages, avoid_print, invalid_use_of_visible_for_testing_member
// Renders the real app for the store screenshots: the whole app with fakes
// behind its ports, driven through one string (Ready, running, finished,
// Review), then Saved drills, Settings (Par), History and Test microphone.
// One PNG per screen, in the app language given.
//
//   flutter test branding/store-listing/render/store_shots_test.dart
//     --dart-define=PLATFORM=ios|android --dart-define=LOCALE=de
//     --dart-define=OUT=<folder> [--dart-define=SIZE=669x951]
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/app.dart';
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/par_config.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/screens/mic_test_screen.dart';
import 'package:simple_shot_timer/services/audio_service.dart';
import 'package:simple_shot_timer/services/database_service.dart';
import 'package:simple_shot_timer/services/settings_service.dart';
import 'package:simple_shot_timer/services/shot_detector.dart';
import 'package:simple_shot_timer/services/timer_ports.dart';
import 'package:simple_shot_timer/services/volume_service.dart';

const platform = String.fromEnvironment('PLATFORM', defaultValue: 'ios');
const localeCode = String.fromEnvironment('LOCALE', defaultValue: 'en');
const outDir = String.fromEnvironment('OUT');

/// Another screen than the iPhone or Android phone of the listing, in
/// logical pixels, e.g. 669x951 (to see how the app lays out there).
const sizeArg = String.fromEnvironment('SIZE');

/// The mic: hears what the script says.
class _Detector implements ShotDetector {
  final _events = StreamController<int>.broadcast();
  final _onsets = StreamController<int>.broadcast();
  Stopwatch? clock;
  int? armedAt;
  double peak = 0;

  void shotAt(int ms) => _events.add(armedAt! + ms);

  @override
  Future<bool> hasPermission() async => true;
  @override
  Stream<int> get events => _events.stream;
  @override
  Stream<int> get beepOnsetEvents => _onsets.stream;
  @override
  double get lastPeak => peak;
  @override
  double? get lastDominantFreqHz => 1840;
  @override
  double get lastDominantFreqStrength => 1;
  @override
  Future<void> start({
    required Stopwatch clock,
    required double threshold,
    required int echoFilterMs,
    int blankingMs = 0,
    bool bandFilterEnabled = false,
    int bandLowHz = 0,
    int bandHighHz = 0,
  }) async {
    this.clock = clock;
  }

  @override
  Future<void> startMonitoring({
    bool bandFilterEnabled = false,
    int bandLowHz = 0,
    int bandHighHz = 0,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  void armBeepDetection() => armedAt ??= clock!.elapsedMilliseconds;
  @override
  void cancelBeepDetection() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements AudioService {
  @override
  Future<void> playStartBeep({required double volume}) async {}
  @override
  Future<void> playParBeep({required double volume}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Env implements RunEnvironment {
  @override
  Future<void> setKeepAwake(bool on) async {}
  @override
  Future<void> setForeground(bool on) async {}
  @override
  Future<void> vibrate() async {}
}

class _Volume extends VolumeService {
  @override
  Future<bool?> isMediaAudible() async => true;
}

/// The history, in memory.
class _Db implements DatabaseService {
  _Db(this.strings);
  final List<TimerString> strings;
  var _nextId = 100;

  @override
  Future<TimerString> insertString(TimerString s,
      {required int historyCap}) async {
    final id = ++_nextId;
    final saved = s.copyWith(
      id: id,
      createdAt: DateTime(2026, 11, 12, 9, 41),
      shots: [
        for (var i = 0; i < s.shots.length; i++)
          s.shots[i].copyWith(id: 100 * id + i, stringId: id, index: i),
      ],
    );
    strings.insert(0, saved);
    return saved;
  }

  @override
  Future<List<TimerString>> listStrings({int limit = 200, int offset = 0}) async =>
      List.of(strings);
  @override
  Future<TimerString?> getString(int id) async =>
      strings.where((s) => s.id == id).firstOrNull;
  @override
  Future<int> countStrings() async => strings.length;
  @override
  Future<void> replaceShots(int stringId, List<Shot> shots) async {
    final i = strings.indexWhere((s) => s.id == stringId);
    strings[i] = strings[i].copyWith(shots: List.of(shots));
  }

  @override
  Future<void> updateStringMeta(int id,
      {String? label, String? notes, int? penaltyMs}) async {
    final i = strings.indexWhere((s) => s.id == id);
    strings[i] = strings[i]
        .copyWith(label: label, notes: notes, penaltyMs: penaltyMs);
  }

  @override
  Future<void> pruneToCap(int historyCap) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TimerString _old(int id, DateTime at, List<int> shots,
        {DrillMode mode = DrillMode.standard,
        String? label,
        int? parMs,
        int? repeat,
        int? intervalMs}) =>
    TimerString(
      id: id,
      createdAt: at,
      drillMode: mode,
      delayMode: DelayMode.random,
      delayUsedMs: 2210,
      pars: [if (parMs != null) ParConfig(enabled: true, durationMs: parMs)],
      parRepeatCount: repeat,
      parIntervalMs: intervalMs,
      label: label,
      shots: [
        for (var i = 0; i < shots.length; i++)
          Shot(id: id * 100 + i, stringId: id, index: i, timeMs: shots[i]),
      ],
    );

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final ios = platform == 'ios';

  setUpAll(() async {
    final sdk =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = [
      for (final w in ['Regular', 'Medium', 'Bold']) '$sdk/Roboto-$w.ttf',
    ];
    // What Chrome on this machine draws for -apple-system.
    const segoe = [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/seguisb.ttf',
      'C:/Windows/Fonts/segoeuib.ttf',
    ];
    await _font('Roboto', roboto);
    await _font('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
    await _font('Montserrat', ['assets/fonts/Montserrat-ExtraBoldItalic.ttf']);
    for (final family in ['Segoe UI', 'Arial', 'sans-serif', 'FlutterTest']) {
      await _font(family, ios ? segoe : roboto);
    }
    if (ios) {
      for (final family in [
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.SF Pro Text',
        '.SF Pro Display',
        '.SF UI Text',
        '.SF UI Display',
      ]) {
        await _font(family, segoe);
      }
    }
  });

  testWidgets('store screenshots', (tester) async {
    if (ios) debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var logical = ios ? const Size(393, 852) : const Size(390, 845);
    if (sizeArg.isNotEmpty) {
      final wh = sizeArg.split('x').map(double.parse).toList();
      logical = Size(wh[0], wh[1]);
    }
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = logical * 3;
    tester.view.padding = FakeViewPadding(
        top: (ios ? 59 : 24) * 3.0, bottom: (ios ? 34 : 20) * 3.0);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);

    DrillConfig drill(DrillMode mode, DelayMode delay,
            {int fixed = 2000,
            int par = 2000,
            int repeat = 5,
            int interval = 5000,
            int stage = 60000,
            int sensitivity = 15}) =>
        DrillConfig(
          drillMode: mode,
          delayMode: delay,
          fixedDelayMs: fixed,
          randomDelayMinMs: 1000,
          randomDelayMaxMs: 4000,
          parDurationMs: par,
          parRepeatCount: repeat,
          parIntervalMs: interval,
          stageDurationMs: stage,
          sensitivityPercent: sensitivity,
        );
    final presidente = drill(DrillMode.standard, DelayMode.random);
    final drills = [
      CustomDrill(id: 1, name: 'El Presidente', config: presidente),
      CustomDrill(
          id: 2,
          name: 'Bill Drill',
          config: drill(DrillMode.standard, DelayMode.fixed, sensitivity: 20)),
      CustomDrill(
          id: 3,
          name: 'Draw',
          config: drill(DrillMode.par, DelayMode.random, par: 1500)),
      CustomDrill(
          id: 4,
          name: 'Stage 1',
          config: drill(DrillMode.stage, DelayMode.random, sensitivity: 25)),
      CustomDrill(
          id: 5,
          name: 'Dot Torture',
          config: drill(DrillMode.standard, DelayMode.instant, sensitivity: 10)),
    ];
    SharedPreferences.setMockInitialValues({
      ...presidente.toMap().cast<String, Object>(),
      'theme_mode': 'dark',
      'locale_code': localeCode,
      'audio_latency_offset_ms': 0,
      'visual_flash': false,
      'custom_drills': CustomDrill.encodeList(drills),
    });
    final prefs = await SettingsService.openPrefs();

    final db = _Db([
      _old(6, DateTime(2026, 11, 12, 9, 36), [1010, 1180, 1340, 1500, 1670, 1840],
          label: 'Bill Drill'),
      _old(5, DateTime(2026, 11, 11, 18, 12), [1390, 1620, 1890, 2140, 2400, 4120],
          mode: DrillMode.par, parMs: 2000, repeat: 5, intervalMs: 5000),
      _old(4, DateTime(2026, 11, 11, 17, 58), [3100, 9800, 21500, 33900, 48200],
          mode: DrillMode.stage, label: 'Stage 1'),
      _old(3, DateTime(2026, 11, 9, 19, 5), [1510, 1790, 2060, 2330, 2610]),
      _old(2, DateTime(2026, 11, 9, 18, 52), [1380],
          mode: DrillMode.par, parMs: 1500, repeat: 5, intervalMs: 5000,
          label: 'Draw'),
      _old(1, DateTime(2026, 11, 8, 10, 14), [1620, 1930, 2250, 2560, 2880]),
    ]);
    final detector = _Detector();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      audioServiceProvider.overrideWithValue(_Audio()),
      shotDetectorProvider.overrideWithValue(detector),
      runEnvironmentProvider.overrideWithValue(_Env()),
      volumeServiceProvider.overrideWithValue(_Volume()),
    ]);

    final shot = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: shot, child: const SimpleShotTimerApp()),
    ));

    Future<void> settle([int ticks = 12]) async {
      for (var i = 0; i < ticks; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // The i18n file loads off the test clock.
    for (var i = 0; find.byType(NavigationBar).evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await settle();

    Future<void> save(String name) async {
      await tester.pump();
      final png = (await tester.runAsync(() async {
        final boundary =
            shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }))!;
      Directory(outDir).createSync(recursive: true);
      File('$outDir/$name.png').writeAsBytesSync(png);
      print('wrote $name');
    }

    Future<void> tab(int i) async {
      await tester.tap(find.byType(NavigationDestination).at(i));
      await settle();
    }

    // A string: START, the beep, five shots, STOP.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(detector.armedAt, isNotNull, reason: 'no beep');
    for (final ms in [1421, 1681, 1911]) {
      detector.shotAt(ms);
    }
    await settle(3);
    await save('running');
    detector
      ..shotAt(2151)
      ..shotAt(2371);
    await settle(3);
    await tester.tap(find.byIcon(Icons.stop));
    await settle();
    await save('total');

    // Its Review, with a label.
    await tester.tap(find.byIcon(Icons.list_alt));
    await settle();
    await tester.enterText(find.byType(TextField).first, 'El Presidente');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(8);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle();
    await save('review');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle();

    await tab(1);
    await save('drills');
    await tab(0);
    await save('ready');

    await tab(3);
    await save('history');

    await tab(4);
    final par = find.byType(ChoiceChip).at(1);
    await tester.tap(par);
    await settle();
    await save('settings');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(navigator
        .push(MaterialPageRoute<void>(builder: (_) => const MicTestScreen())));
    await settle();
    detector.peak = 0.94;
    await settle(3);
    detector.peak = 0.62;
    await settle(2);
    await save('mic');

    // Leaving the mic test throws in its dispose (ref.read after unmount),
    // so the test ends on it; what the framework reports while it takes
    // the tree down is not about the pictures.
    FlutterError.onError = (_) {};

    debugDefaultTargetPlatformOverride = null;
  });
}
