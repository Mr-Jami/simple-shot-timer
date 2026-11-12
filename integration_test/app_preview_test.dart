// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/main.dart' as app;
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/par_config.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/history_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/screens/main_shell.dart';
import 'package:simple_shot_timer/services/database_service.dart';
import 'package:simple_shot_timer/services/settings_service.dart';
import 'package:simple_shot_timer/services/timer_ports.dart';
import 'package:simple_shot_timer/services/volume_service.dart';

/// Plays the App Store preview video's story in the real app, so a screen
/// recording of the simulator is the video: Ready, START, the beep, five
/// shots with their splits, STOP, the total, Review, History, Video, Saved
/// drills and Ready again.
///
/// Only what a simulator cannot supply is scripted: the microphone (the shots
/// arrive at set times), the beep (silent), the clock a string is saved with
/// (9:41, the time the status bar is set to) and the history and drills
/// already on the phone, which are those of the store screenshots
/// (branding/store-listing). Every screen is the app's own.
///
/// `.github/workflows/app-preview.yml` records it;
/// branding/store-listing/README.md says how the recording becomes the
/// video. To run it by hand, in a simulator or on a spare phone (it replaces
/// the app's history, drills and settings with its own):
///
///     flutter test integration_test/app_preview_test.dart -d <device>

/// The shots of the string, in milliseconds after the beep: the string of the
/// store screenshots (first shot 1.42 s, total 2.37 s).
const _shotsMs = [1420, 1680, 1910, 2150, 2370];

/// The random start delay drawn for the string. The Review screen of the
/// store screenshots shows it.
const _delayMs = 1580;

/// When the string is fired: the day of the store screenshots, at the time
/// on the status bar.
final _now = DateTime(2026, 10, 1, 9, 41);

// How long each screen stays, in the order of the story. The video is cut
// from 1.6 s before the tap on START to 1.9 s after the last tap (see the
// README), so these add up to about 25 s of it.
const _afterLastShot = Duration(milliseconds: 950);
const _onTotal = Duration(milliseconds: 2900);
const _onReview = Duration(milliseconds: 3400);
const _onReadyBetween = Duration(milliseconds: 1100);
const _onHistory = Duration(milliseconds: 3000);
const _onVideo = Duration(milliseconds: 2800);
const _onDrills = Duration(milliseconds: 3000);

/// Ready before the first tap and after the last one. Longer than the video
/// shows, so the cut never lands on a moving frame.
const _hold = Duration(milliseconds: 4000);

const _settings = AppSettings(
  themeMode: AppThemeMode.dark,
  localeCode: 'en',
  // Minimum and maximum alike: "Random delay" on the chips, [_delayMs] on
  // every run.
  randomDelayMinMs: _delayMs,
  randomDelayMaxMs: _delayMs,
);

/// The saved drills of the store screenshots, and three more for the taller
/// screen. The first equals [_settings], so it is the active one.
final _drills = [
  for (final (i, (name, settings)) in [
    ('El Presidente', _settings),
    (
      'Bill Drill',
      _settings.copyWith(delayMode: DelayMode.fixed, fixedDelayMs: 2000),
    ),
    (
      'Draw drill',
      _settings.copyWith(
        drillMode: DrillMode.par,
        parDurationMs: 1500,
        parRepeatCount: 5,
      ),
    ),
    ('Stage warm-up', _settings.copyWith(drillMode: DrillMode.stage)),
    ('Dot torture', _settings.copyWith(delayMode: DelayMode.instant)),
    (
      'Reload drill',
      _settings.copyWith(
        drillMode: DrillMode.par,
        delayMode: DelayMode.fixed,
        fixedDelayMs: 3000,
        parDurationMs: 3500,
      ),
    ),
    ('Dry fire at home', _settings.copyWith(sensitivityPercent: 60)),
    (
      'Weak hand only',
      _settings.copyWith(
        drillMode: DrillMode.par,
        parDurationMs: 2500,
        parRepeatCount: 3,
      ),
    ),
  ].indexed)
    CustomDrill(
      id: i + 1,
      name: name,
      config: DrillConfig.fromSettings(settings),
    ),
];

TimerString _standard(
  DateTime at,
  List<int> shotsMs, {
  String? label,
  int delayUsedMs = 2140,
}) =>
    TimerString(
      createdAt: at,
      drillMode: DrillMode.standard,
      delayMode: DelayMode.random,
      delayUsedMs: delayUsedMs,
      pars: const [],
      shots: [
        for (final (i, ms) in shotsMs.indexed) Shot(index: i, timeMs: ms),
      ],
      label: label,
    );

/// A par string of [cycles], each a list of shot times.
TimerString _par(
  DateTime at,
  int parMs,
  List<List<int>> cycles, {
  String? label,
}) {
  var index = 0;
  return TimerString(
    createdAt: at,
    drillMode: DrillMode.par,
    delayMode: DelayMode.random,
    delayUsedMs: 2760,
    pars: [ParConfig(enabled: true, durationMs: parMs)],
    parRepeatCount: cycles.length,
    parIntervalMs: 5000,
    shots: [
      for (final (cycle, shotsMs) in cycles.indexed)
        for (final ms in shotsMs)
          Shot(index: index++, timeMs: ms, cycleIndex: cycle + 1),
    ],
    label: label,
  );
}

/// The History of the store screenshots without its newest string (the test
/// fires that one), and three older ones for the taller screen.
final _history = [
  _standard(
    DateTime(2026, 10, 1, 9, 36),
    [940, 1120, 1300, 1480, 1660, 1840],
    label: 'Bill Drill, cold',
  ),
  _par(DateTime(2026, 9, 30, 18, 12), 2000, [
    [1710],
    [1640],
    [1690],
    [1580],
    [1620, 4120],
  ]),
  TimerString(
    createdAt: DateTime(2026, 9, 30, 17, 58),
    drillMode: DrillMode.stage,
    delayMode: DelayMode.random,
    delayUsedMs: 3310,
    pars: const [ParConfig(enabled: true, durationMs: 60000)],
    shots: [
      for (final (i, ms) in const [
        2180, 2450, 6900, 7160, 13400, 13690, 21750, 22010, 30300, 30580, //
        39100, 39370, 47920, 48200,
      ].indexed)
        Shot(index: i, timeMs: ms),
    ],
    label: 'Stage 1 walk-through',
  ),
  _standard(DateTime(2026, 9, 28, 19, 5), [1510, 1790, 2060, 2340, 2610]),
  _par(
    DateTime(2026, 9, 28, 18, 52),
    1500,
    [
      [1460],
      [1410],
      [1440],
      [1350],
      [1380],
    ],
    label: 'Draw drill',
  ),
  _standard(DateTime(2026, 9, 27, 10, 14), [1630, 1950, 2260, 2570, 2880]),
  _standard(
    DateTime(2026, 9, 27, 10, 2),
    [1080, 1270, 1470, 1660, 1860, 2050],
    label: 'Bill Drill',
  ),
  _standard(
    DateTime(2026, 9, 25, 18, 40),
    [1380, 1640, 3170, 3420],
    label: 'Reload drill',
  ),
  _standard(
    DateTime(2026, 9, 24, 18, 21),
    [1570, 1880, 2190, 2500, 2810, 3120],
  ),
];

/// The microphone of the recording: no sound, a script. From the moment the
/// timer asks for the beep it reports the beep's onset and then the shots of
/// [shotsMs], each when it is due, as the detector would.
class _ScriptedMicrophone implements ShotSource {
  _ScriptedMicrophone(this.shotsMs);

  final List<int> shotsMs;

  /// How long the beep takes to come out of a phone's speaker.
  static const _beepLatencyMs = 40;

  final _events = StreamController<int>.broadcast();
  final _onsets = StreamController<int>.broadcast();
  final _timers = <Timer>[];
  final _noise = math.Random(941);
  Stopwatch? _clock;
  int _soundAtMs = 0;
  double _soundLevel = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<int> get events => _events.stream;

  @override
  Stream<int> get beepOnsetEvents => _onsets.stream;

  /// A quiet room, and each sound dying away: what the level line of the
  /// running screen draws.
  @override
  double get lastPeak {
    final floor = 0.02 + 0.03 * _noise.nextDouble();
    final clock = _clock;
    if (clock == null) return floor;
    final age = clock.elapsedMilliseconds - _soundAtMs;
    return math.max(floor, _soundLevel * math.exp(-age / 110));
  }

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
    _clock = clock;
    _soundLevel = 0;
  }

  @override
  Future<void> stop() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _clock = null;
  }

  @override
  void armBeepDetection() {
    final clock = _clock;
    if (clock == null) return;
    final onsetMs = clock.elapsedMilliseconds + _beepLatencyMs;
    _at(clock, onsetMs, 0.3, () => _onsets.add(onsetMs));
    for (final ms in shotsMs) {
      _at(clock, onsetMs + ms, 0.97, () => _events.add(onsetMs + ms));
    }
  }

  @override
  void cancelBeepDetection() {}

  void _at(Stopwatch clock, int ms, double level, void Function() report) {
    final wait = math.max(0, ms - clock.elapsedMilliseconds);
    _timers.add(Timer(Duration(milliseconds: wait), () {
      _soundAtMs = ms;
      _soundLevel = level;
      report();
    }));
  }
}

/// A simulator in CI has no speaker anyone hears.
class _SilentBeep implements BeepPlayer {
  @override
  Future<void> playStartBeep({required double volume}) async {}

  @override
  Future<void> playParBeep({required double volume}) async {}
}

/// The app's database, with every new string saved at [_now]: the status
/// bar of the recording says 9:41 whatever the time in CI.
class _StoreAtNow implements StringStore {
  _StoreAtNow(this._db);

  final DatabaseService _db;

  @override
  Future<TimerString> insertString(TimerString s, {required int historyCap}) =>
      _db.insertString(s.copyWith(createdAt: _now), historyCap: historyCap);

  @override
  Future<void> replaceShots(int stringId, List<Shot> shots) =>
      _db.replaceShots(stringId, shots);

  @override
  Future<void> updateStringMeta(
    int id, {
    String? label,
    String? notes,
    int? penaltyMs,
  }) =>
      _db.updateStringMeta(id,
          label: label, notes: notes, penaltyMs: penaltyMs);
}

/// No foreground service (on iOS it would ask to send notifications), no
/// wake lock and no haptics.
class _NoEnvironment implements RunEnvironment {
  @override
  Future<void> setKeepAwake(bool on) async {}

  @override
  Future<void> setForeground(bool on) async {}

  @override
  Future<void> vibrate() async {}
}

/// A simulator's volume would put "Media volume is off" on the screen.
class _AudibleVolume extends VolumeService {
  @override
  Future<bool?> isMediaAudible() async => true;
}

/// Replaces what the app has stored with [_settings], [_drills] and
/// [_history].
Future<void> _seed() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final settings = SettingsService(prefs);
  await settings.save(_settings);
  await settings.saveDrills(_drills);

  final db = await DatabaseService.open();
  await db.deleteAll();
  for (final string in _history) {
    await db.insertString(string, historyCap: _settings.historyCap);
  }
  await db.close();
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

/// Waits until [finder] finds something, in real time: the app draws its
/// frames by itself.
Future<void> _until(
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (watch.elapsed > timeout) fail('not on screen after $timeout: $finder');
    await _wait(const Duration(milliseconds: 16));
  }
}

/// A line in the test's output that says when [step] happened, so the
/// recording can be cut (see the README).
void _mark(String step) {
  // ignore: avoid_print
  print('PREVIEW_MARK $step ${DateTime.now().millisecondsSinceEpoch}');
}

Finder _tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Every frame the app asks for, not only those a test pumps.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    // Taps go in the way a finger's do. Sent as a test's, the binding would
    // draw a crosshair on each.
    ..shouldPropagateDevicePointerEvents = true;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    final gesture = TestGesture(
      dispatcher: (event) async => binding.handlePointerEvent(event),
    );
    await gesture.down(tester.getCenter(finder));
    await _wait(const Duration(milliseconds: 90));
    await gesture.up();
  }

  testWidgets('plays the App Store preview', (tester) async {
    // The binding draws the test's name along the top edge of the screen.
    // ignore: invalid_use_of_protected_member
    binding.setLabel('');
    final microphone = _ScriptedMicrophone(_shotsMs);
    await _seed();
    await app.startApp(overrides: [
      shotSourceProvider.overrideWithValue(microphone),
      beepPlayerProvider.overrideWithValue(_SilentBeep()),
      stringStoreProvider.overrideWith(
        (ref) => _StoreAtNow(ref.watch(databaseProvider)),
      ),
      runEnvironmentProvider.overrideWithValue(_NoEnvironment()),
      volumeServiceProvider.overrideWithValue(_AudibleVolume()),
    ]);

    final start = find.text('START');
    final stop = find.text('STOP');
    final ready = find.text('Ready');
    final lastSeeded = find.text('Last 1.84s · 6 shots');
    await _until(lastSeeded);
    expect(find.text('El Presidente'), findsOneWidget);
    expect(find.text('Random delay'), findsOneWidget);

    // Once through everything before the recording counts: the first run of
    // a screen in a debug build stutters. One shot, then every screen of
    // the story; the string goes again afterwards.
    await tap(tester, start);
    await _until(find.text('LAST'));
    await _wait(const Duration(milliseconds: 300));
    await tap(tester, stop);
    await _until(find.text('TOTAL'));
    await _wait(const Duration(milliseconds: 500));
    await tap(tester, find.text('Review'));
    await _until(find.text('first'));
    await _wait(const Duration(milliseconds: 800));
    await tap(tester, find.byType(BackButton));
    await _until(ready);
    for (final label in ['History', 'Video', 'Drills', 'Timer']) {
      await _wait(const Duration(milliseconds: 600));
      await tap(tester, _tab(label));
    }
    await _wait(const Duration(milliseconds: 600));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );
    final warmUp = (await container.read(historyProvider.future)).first;
    expect(warmUp.shotCount, 1);
    await container.read(historyProvider.notifier).delete(warmUp.id!);
    await _until(lastSeeded);

    // The story.
    await _wait(_hold);
    _mark('start');
    await tap(tester, start);
    await _until(find.text('STAND BY'));
    await _until(find.text('TIME'));
    _mark('beep');
    await _until(find.text('2.37'));
    _mark('last-shot');
    expect(find.text('5'), findsOneWidget);
    expect(find.text('1.42'), findsOneWidget);
    expect(find.text('0.22s'), findsOneWidget);
    await _wait(_afterLastShot);

    _mark('stop');
    await tap(tester, stop);
    await _until(find.text('TOTAL'));
    expect(find.text('2.37'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Saved 9:41\sAM$')), findsOneWidget);
    await _wait(_onTotal);

    _mark('review');
    await tap(tester, find.text('Review'));
    await _until(find.text('split 0.22s'));
    expect(
      find.textContaining(RegExp(r'^Oct 1, 2026 9:41\sAM$')),
      findsOneWidget,
    );
    expect(find.text('Standard · Random (1.58s delay)'), findsOneWidget);
    for (final split in [
      'first',
      'split 0.26s',
      'split 0.23s',
      'split 0.24s'
    ]) {
      expect(find.text(split), findsOneWidget);
    }
    await _wait(_onReview);

    _mark('back');
    await tap(tester, find.byType(BackButton));
    await _until(find.text('Last 2.37s · 5 shots'));
    await _wait(_onReadyBetween);

    _mark('history');
    await tap(tester, _tab('History'));
    await _until(find.text('2.37s · 5 shots'));
    expect(find.text('Bill Drill, cold'), findsOneWidget);
    await _wait(_onHistory);

    _mark('video');
    await tap(tester, _tab('Video'));
    await _until(find.text('Choose video'));
    await _wait(_onVideo);

    _mark('drills');
    await tap(tester, _tab('Drills'));
    await _until(find.text('Saved drills'));
    expect(find.text('Bill Drill'), findsOneWidget);
    await _wait(_onDrills);

    _mark('timer');
    await tap(tester, _tab('Timer'));
    await _until(ready);
    expect(find.text('Last 2.37s · 5 shots'), findsOneWidget);
    await _wait(_hold);
    _mark('end');
  });
}
