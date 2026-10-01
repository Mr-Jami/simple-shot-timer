import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/settings_provider.dart';
import 'package:simple_shot_timer/providers/timer_provider.dart';
import 'package:simple_shot_timer/services/timer_ports.dart';
import 'package:simple_shot_timer/services/volume_service.dart';

/// Drives a whole run through `TimerNotifier` with fakes behind the four
/// ports, under FakeAsync so beep delays and save latency are deterministic.

class _FakeShotSource implements ShotSource {
  int startCalls = 0;
  int stopCalls = 0;

  /// How long the mic takes to come up; zero completes at once.
  Duration startDelay = Duration.zero;
  bool failStart = false;
  final _events = StreamController<int>.broadcast();
  final _onsets = StreamController<int>.broadcast();

  @override
  Future<bool> hasPermission() async => true;
  @override
  Stream<int> get events => _events.stream;
  @override
  Stream<int> get beepOnsetEvents => _onsets.stream;
  @override
  double get lastPeak => 0;
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
    startCalls++;
    if (startDelay > Duration.zero) await Future.delayed(startDelay);
    if (failStart) throw StateError('mic busy');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
  @override
  void armBeepDetection() {}
  @override
  void cancelBeepDetection() {}
}

class _FakeBeepPlayer implements BeepPlayer {
  int startBeeps = 0;
  int parBeeps = 0;
  @override
  Future<void> playStartBeep({required double volume}) async => startBeeps++;
  @override
  Future<void> playParBeep({required double volume}) async => parBeeps++;
}

class _FakeEnvironment implements RunEnvironment {
  int vibrations = 0;
  @override
  Future<void> setKeepAwake(bool on) async {}
  @override
  Future<void> setForeground(bool on) async {}
  @override
  Future<void> vibrate() async => vibrations++;
}

class _MemoryStore implements StringStore {
  final List<TimerString> strings = [];
  Duration insertDelay = Duration.zero;
  bool failInserts = false;
  int _nextId = 0;

  @override
  Future<TimerString> insertString(
    TimerString s, {
    required int historyCap,
  }) async {
    if (insertDelay > Duration.zero) await Future.delayed(insertDelay);
    if (failInserts) throw StateError('disk full');
    final id = ++_nextId;
    final saved = s.copyWith(
      id: id,
      shots: [
        for (var i = 0; i < s.shots.length; i++)
          s.shots[i].copyWith(id: 100 * id + i, stringId: id, index: i),
      ],
    );
    strings.add(saved);
    return saved;
  }

  @override
  Future<void> replaceShots(int stringId, List<Shot> shots) async {
    final i = strings.indexWhere((s) => s.id == stringId);
    strings[i] = strings[i].copyWith(shots: List.of(shots));
  }

  @override
  Future<void> updateStringMeta(
    int id, {
    String? label,
    String? notes,
    int? penaltyMs,
  }) async {}
}

class _AudibleVolume extends VolumeService {
  @override
  Future<bool?> isMediaAudible() async => true;
}

class _Harness {
  _Harness(SharedPreferences prefs)
      : container = ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          shotSourceProvider.overrideWithValue(source),
          beepPlayerProvider.overrideWithValue(beeps),
          stringStoreProvider.overrideWithValue(store),
          runEnvironmentProvider.overrideWithValue(env),
          volumeServiceProvider.overrideWithValue(_AudibleVolume()),
        ]);

  static final source = _FakeShotSource();
  static final beeps = _FakeBeepPlayer();
  static final store = _MemoryStore();
  static final env = _FakeEnvironment();
  final ProviderContainer container;

  TimerNotifier get timer => container.read(timerProvider.notifier);
  TimerPhase get phase => container.read(timerProvider).phase;
  int get flashTick => container.read(timerProvider).flashTick;

  void settings(AppSettings Function(AppSettings) update, FakeAsync async) {
    container.read(settingsProvider.notifier).update(update);
    async.flushMicrotasks();
  }

  /// Instant-start run: START, then let setup and the start beep land.
  void startRun(FakeAsync async) {
    timer.start();
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 10));
  }

  void stopRun(FakeAsync async) {
    timer.stop();
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    _Harness.store.strings.clear();
    _Harness.store.insertDelay = Duration.zero;
    _Harness.store.failInserts = false;
    _Harness.source
      ..startCalls = 0
      ..stopCalls = 0
      ..startDelay = Duration.zero
      ..failStart = false;
    _Harness.beeps
      ..startBeeps = 0
      ..parBeeps = 0;
    _Harness.env.vibrations = 0;
  });

  group('a run that detected nothing', () {
    test('is not saved, and adding a shot by hand saves it once even on a '
        'double tap', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings((s) => s.copyWith(delayMode: DelayMode.instant), async);

        h.startRun(async);
        expect(h.phase, TimerPhase.running);
        h.stopRun(async);
        expect(h.container.read(timerProvider).nothingRecorded, isTrue);
        expect(_Harness.store.strings, isEmpty);

        _Harness.store.insertDelay = const Duration(milliseconds: 50);
        h.timer.addManualShot();
        h.timer.addManualShot(); // second tap while the first save is in flight
        async.elapse(const Duration(milliseconds: 200));

        expect(_Harness.store.strings, hasLength(1));
        expect(_Harness.store.strings.single.shots, hasLength(2));
        final state = h.container.read(timerProvider);
        expect(state.savedStringId, _Harness.store.strings.single.id);
        expect(state.shots, hasLength(2));
        expect(state.error, isNull);
      });
    });

    test('a failed save is reported and can be retried', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings((s) => s.copyWith(delayMode: DelayMode.instant), async);
        h.startRun(async);
        h.stopRun(async);

        _Harness.store.failInserts = true;
        h.timer.addManualShot();
        async.elapse(const Duration(milliseconds: 10));
        expect(h.container.read(timerProvider).error, 'errors.saveFailed');
        expect(h.container.read(timerProvider).savedStringId, isNull);

        _Harness.store.failInserts = false;
        h.timer.addManualShot();
        async.elapse(const Duration(milliseconds: 10));
        expect(_Harness.store.strings, hasLength(1));
        expect(_Harness.store.strings.single.shots, hasLength(2));
      });
    });
  });

  group('beep signals', () {
    test('flash and haptic are delayed by the latency estimate', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings(
          (s) => s.copyWith(
            delayMode: DelayMode.instant,
            hapticOnBeep: true,
            beepLatencyEstimateMs: 200,
          ),
          async,
        );
        h.timer.start();
        async.flushMicrotasks();
        expect(h.phase, TimerPhase.running);
        expect(_Harness.beeps.startBeeps, 1);

        async.elapse(const Duration(milliseconds: 150));
        expect(h.flashTick, 0, reason: 'signals wait for the audible beep');
        expect(_Harness.env.vibrations, 0);

        async.elapse(const Duration(milliseconds: 100));
        expect(h.flashTick, 1);
        expect(_Harness.env.vibrations, 1);
      });
    });

    test('the flash counter survives a new run, so the start flash shows',
        () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings((s) => s.copyWith(delayMode: DelayMode.instant), async);

        h.startRun(async);
        async.elapse(const Duration(milliseconds: 100));
        expect(h.flashTick, 1);
        h.stopRun(async);

        h.startRun(async);
        expect(h.flashTick, 1, reason: 'no reset to zero on re-run');
        async.elapse(const Duration(milliseconds: 100));
        expect(h.flashTick, 2, reason: 'the new start beep still flashes');
      });
    });

    test('pending signals are cancelled by STOP', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings(
          (s) => s.copyWith(
            delayMode: DelayMode.instant,
            drillMode: DrillMode.par,
            parDurationMs: 2000,
            parRepeatCount: 1,
            beepLatencyEstimateMs: 300,
          ),
          async,
        );
        h.startRun(async);
        async.elapse(const Duration(milliseconds: 400));
        expect(h.flashTick, 1);

        // Par beep fires at 2.0 s; stop 100 ms after it, before its signal.
        async.elapse(const Duration(milliseconds: 1700));
        expect(_Harness.beeps.parBeeps, 1);
        h.stopRun(async);
        async.elapse(const Duration(seconds: 3));
        expect(h.flashTick, 1, reason: 'no flash after the run ended');
      });
    });
  });

  group('double taps', () {
    test('START twice starts one run', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings((s) => s.copyWith(delayMode: DelayMode.instant), async);
        h.timer.start();
        h.timer.start();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        expect(h.phase, TimerPhase.running);
        expect(_Harness.source.startCalls, 1);
      });
    });

    test('STOP while the mic is still starting cancels the run', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings(
          (s) => s.copyWith(delayMode: DelayMode.fixed, fixedDelayMs: 2000),
          async,
        );
        _Harness.source.startDelay = const Duration(milliseconds: 500);
        h.timer.start();
        async.flushMicrotasks();
        expect(h.phase, TimerPhase.countdown,
            reason: 'the countdown shows before the mic is up');

        h.timer.stop(); // during the mic start
        async.elapse(const Duration(milliseconds: 100));
        expect(h.phase, TimerPhase.countdown,
            reason: 'nothing to tear down yet; the cancel waits for the mic');

        async.elapse(const Duration(milliseconds: 500));
        expect(h.phase, TimerPhase.idle);
        expect(_Harness.source.stopCalls, 1);
        async.elapse(const Duration(seconds: 3));
        expect(_Harness.beeps.startBeeps, 0, reason: 'no beep after cancel');
        expect(_Harness.store.strings, isEmpty);
      });
    });

    test('a mic that fails to start returns to idle with an error', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings(
          (s) => s.copyWith(delayMode: DelayMode.fixed, fixedDelayMs: 2000),
          async,
        );
        _Harness.source.failStart = true;
        h.timer.start();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        final state = h.container.read(timerProvider);
        expect(state.phase, TimerPhase.idle);
        expect(state.error, 'errors.micStartFailed');
        async.elapse(const Duration(seconds: 3));
        expect(_Harness.beeps.startBeeps, 0);
      });
    });

    test('STOP twice saves one string', () {
      fakeAsync((async) {
        final h = _Harness(prefs);
        h.settings((s) => s.copyWith(delayMode: DelayMode.instant), async);
        h.startRun(async);
        h.timer.addManualShot();
        async.flushMicrotasks();

        _Harness.store.insertDelay = const Duration(milliseconds: 50);
        h.timer.stop();
        h.timer.stop();
        async.elapse(const Duration(milliseconds: 200));
        expect(h.phase, TimerPhase.finished);
        expect(_Harness.store.strings, hasLength(1));
        expect(_Harness.store.strings.single.shots, hasLength(1));
      });
    });
  });
}
