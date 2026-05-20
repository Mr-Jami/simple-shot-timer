import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';
import '../models/par_config.dart';
import '../models/par_schedule.dart';
import '../models/shot.dart';
import '../models/timer_state.dart';
import '../services/background_service.dart';
import '../models/timer_string.dart';
import 'providers.dart';
import 'settings_provider.dart';

class TimerNotifier extends Notifier<TimerState> {
  final Stopwatch _clock = Stopwatch();
  Timer? _beepTimer;
  Timer? _tickTimer;
  final List<Timer> _parTimers = [];
  StreamSubscription<int>? _detectionSub;

  /// Master-clock timestamp when the *current* cycle's beep fired. Shot
  /// timestamps and the on-screen elapsed counter are both measured from
  /// here, so each par cycle reads from 0.
  int _cycleStartClockMs = 0;

  /// Currently-active par cycle (1..N). For non-par/single-cycle runs this
  /// stays at 1 throughout.
  int _currentCycle = 1;

  AppSettings _snapshot = const AppSettings();
  DrillMode _runMode = DrillMode.standard;
  DelayMode _runDelayMode = DelayMode.instant;

  @override
  TimerState build() {
    ref.onDispose(_cleanup);
    return TimerState.idle();
  }

  Future<void> start() async {
    if (state.phase != TimerPhase.idle && state.phase != TimerPhase.finished) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final detector = ref.read(shotDetectorProvider);
    if (!await detector.hasPermission()) {
      // Set a translation key; the UI listener resolves it through
      // AppLocalizations so the SnackBar matches the current language.
      state = state.copyWith(error: 'errors.micPermissionDenied');
      return;
    }

    _snapshot = settings;
    _runMode = settings.drillMode;
    _runDelayMode = settings.delayMode;
    final delayMs = _computeDelayMs(settings);

    if (settings.keepScreenAwake) {
      await WakelockPlus.enable();
    }

    // Promote to a foreground service so Android won't suspend the mic
    // stream or kill the beep timers when the user locks the screen or
    // switches apps. On iOS this is a no-op (the audio background mode in
    // Info.plist handles it via the active AVAudioSession).
    await BackgroundService.start();

    // Reset clock but leave it stopped. We delay starting it until after the
    // native mic stream is ready, so the Timer(delayMs) below and the on-screen
    // countdown both measure from the same t=0.
    _clock
      ..stop()
      ..reset();

    // Show the countdown view immediately for instant feedback. elapsedMs stays
    // at 0 (clock not running yet), so the display reads the full delayMs until
    // the clock actually starts a few hundred ms later.
    state = TimerState.idle().copyWith(
      phase: delayMs > 0 ? TimerPhase.countdown : TimerPhase.running,
      delayUsedMs: delayMs,
      clearError: true,
      clearSavedId: true,
    );

    // Subscribe to detections first so the stream is ready when the beep fires.
    _detectionSub = detector.events.listen(_onDetection);
    await detector.start(
      clock: _clock,
      threshold: settings.detectionThreshold,
      echoFilterMs: settings.echoFilterMs,
      // Only blank during the countdown; the detector's notch filter handles
      // the beep itself, so shots fired during/right after the beep still
      // register.
      blankingMs: delayMs,
      bandFilterEnabled: settings.bandFilterEnabled,
      bandLowHz: settings.bandLowHz,
      bandHighHz: settings.bandHighHz,
    );

    // Async setup complete. Start the clock and schedule the beep so the user
    // experiences exactly delayMs of countdown.
    _clock.start();
    _startTick();

    if (delayMs == 0) {
      await _fireStartBeep(silent: false);
    } else {
      _beepTimer = Timer(
        Duration(milliseconds: delayMs),
        () => _fireStartBeep(silent: false),
      );
    }
  }

  Future<void> stop() async {
    if (state.phase != TimerPhase.countdown &&
        state.phase != TimerPhase.running) {
      return;
    }
    await _teardownRun();

    final shots = List<Shot>.from(state.shots);
    if (shots.isEmpty && state.phase == TimerPhase.countdown) {
      // Stopped before the start beep fired — discard.
      state = TimerState.idle();
      return;
    }

    final settings = _snapshot;
    final pars = switch (_runMode) {
      DrillMode.par when settings.parDurationMs > 0 => [
          ParConfig(enabled: true, durationMs: settings.parDurationMs),
        ],
      DrillMode.stage when settings.stageDurationMs > 0 => [
          ParConfig(enabled: true, durationMs: settings.stageDurationMs),
        ],
      _ => const <ParConfig>[],
    };
    final draft = TimerString(
      createdAt: DateTime.now(),
      drillMode: _runMode,
      delayMode: _runDelayMode,
      delayUsedMs: state.delayUsedMs ?? 0,
      pars: pars,
      shots: shots,
      // Capture par-mode structure so the review screen can reconstruct the
      // exact drill the user ran (par duration, repeats, interval).
      parRepeatCount: _runMode == DrillMode.par ? settings.parRepeatCount : null,
      parIntervalMs: _runMode == DrillMode.par ? settings.parIntervalMs : null,
    );

    final db = ref.read(databaseProvider);
    final saved = await db.insertString(draft, historyCap: settings.historyCap);

    state = state.copyWith(
      phase: TimerPhase.finished,
      shots: saved.shots,
      savedStringId: saved.id,
    );
  }

  void reset() {
    _cleanup();
    state = TimerState.idle();
  }

  Future<void> addManualShot() async {
    if (state.phase != TimerPhase.running &&
        state.phase != TimerPhase.finished) {
      return;
    }
    final elapsed = state.phase == TimerPhase.running
        ? _clock.elapsedMilliseconds - _cycleStartClockMs
        : (state.shots.isEmpty
            ? 0
            : state.shots.last.timeMs +
                _snapshot.echoFilterMs.clamp(20, 1000));
    // Inherit the last shot's cycle for post-run additions (so a manual
    // add after the run still groups under the same cycle); use the live
    // cycle counter during a run.
    final cycle = state.phase == TimerPhase.running
        ? _currentCycle
        : (state.shots.isEmpty ? 1 : state.shots.last.cycleIndex);
    final shot = Shot(
      stringId: state.savedStringId,
      index: state.shots.length,
      timeMs: math.max(0, elapsed),
      manual: true,
      cycleIndex: cycle,
    );
    final updated = [...state.shots, shot];
    state = state.copyWith(shots: updated);
    if (state.phase == TimerPhase.finished && state.savedStringId != null) {
      await ref
          .read(databaseProvider)
          .replaceShots(state.savedStringId!, updated);
    }
  }

  Future<void> deleteShot(int index) async {
    if (index < 0 || index >= state.shots.length) return;
    final updated = [
      for (var i = 0; i < state.shots.length; i++)
        if (i != index) state.shots[i],
    ];
    final reindexed = [
      for (var i = 0; i < updated.length; i++)
        updated[i].copyWith(index: i),
    ];
    state = state.copyWith(shots: reindexed);
    if (state.phase == TimerPhase.finished && state.savedStringId != null) {
      await ref
          .read(databaseProvider)
          .replaceShots(state.savedStringId!, reindexed);
    }
  }

  Future<void> updateNotes(String notes) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref.read(databaseProvider).updateStringMeta(id, notes: notes);
  }

  Future<void> updateLabel(String label) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref.read(databaseProvider).updateStringMeta(id, label: label);
  }

  Future<void> updatePenalty(int penaltyMs) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref.read(databaseProvider).updateStringMeta(id, penaltyMs: penaltyMs);
  }

  /// Visible for testing — pure delay computation.
  static int computeDelay(AppSettings s, {math.Random? rng}) =>
      _computeDelayMs(s, rng: rng);

  static int _computeDelayMs(AppSettings s, {math.Random? rng}) {
    switch (s.delayMode) {
      case DelayMode.instant:
        return 0;
      case DelayMode.fixed:
        return math.max(0, s.fixedDelayMs);
      case DelayMode.random:
        final min = math.max(0, s.randomDelayMinMs);
        final max = math.max(min, s.randomDelayMaxMs);
        if (max == min) return min;
        final r = (rng ?? math.Random()).nextInt(max - min + 1);
        return min + r;
    }
  }

  Future<void> _fireStartBeep({required bool silent}) async {
    _beginCycle(1);
    state = state.copyWith(
      phase: TimerPhase.running,
      flashTick: state.flashTick + 1,
    );
    if (!silent) {
      await _playStartBeep();
    }
    _schedulePars();
    _startTick();
  }

  /// Marks the start of a new par cycle: resets the per-cycle clock + state
  /// so shot timestamps and the on-screen elapsed counter both read from 0.
  void _beginCycle(int cycle) {
    _currentCycle = cycle;
    _cycleStartClockMs = _clock.elapsedMilliseconds;
    state = state.copyWith(
      elapsedMs: 0,
      currentParIndex: cycle,
    );
  }

  void _schedulePars() {
    final totalCycles = _runMode == DrillMode.par
        ? _snapshot.parRepeatCount.clamp(1, AppSettings.parRepeatMax)
        : 1;
    final intervalMs = _snapshot.parIntervalMs;
    for (final event in computeParSchedule(_snapshot, _runMode)) {
      _parTimers.add(Timer(Duration(milliseconds: event.timeMs), () {
        // Reset the cycle clock at every cycle boundary. With interval > 0
        // that's the explicit START beep; with interval == 0 the END beep
        // of cycle K doubles as the start of cycle K+1.
        if (event.kind == ParBeepKind.start) {
          _beginCycle(event.cycle);
        } else if (event.kind == ParBeepKind.end &&
            intervalMs == 0 &&
            event.cycle < totalCycles) {
          _beginCycle(event.cycle + 1);
        }
        state = state.copyWith(
          currentParIndex: event.cycle,
          flashTick: state.flashTick + 1,
        );
        if (event.kind == ParBeepKind.start) {
          _playStartBeep();
        } else {
          _playParBeep();
        }
      }));
    }
  }

  Future<void> _playStartBeep() async {
    final audio = ref.read(audioServiceProvider);
    unawaited(audio.playStartBeep(volume: _snapshot.beepVolume));
    await _maybeHaptic();
  }

  Future<void> _playParBeep() async {
    final audio = ref.read(audioServiceProvider);
    unawaited(audio.playParBeep(volume: _snapshot.beepVolume));
    await _maybeHaptic();
  }

  Future<void> _maybeHaptic() async {
    if (!_snapshot.hapticOnBeep) return;
    if (await Vibration.hasVibrator()) {
      unawaited(Vibration.vibrate(duration: 100));
    }
  }

  void _startTick() {
    _tickTimer?.cancel();
    final detector = ref.read(shotDetectorProvider);
    _tickTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (state.phase != TimerPhase.running &&
          state.phase != TimerPhase.countdown) {
        return;
      }
      state = state.copyWith(
        elapsedMs: _clock.elapsedMilliseconds - _cycleStartClockMs,
        micLevel: detector.lastPeak,
      );
    });
  }

  void _onDetection(int clockMs) {
    if (state.phase != TimerPhase.running) return;
    final shotMs = clockMs - _cycleStartClockMs;
    if (shotMs < 0) return;
    final shot = Shot(
      index: state.shots.length,
      timeMs: shotMs,
      cycleIndex: _currentCycle,
    );
    state = state.copyWith(shots: [...state.shots, shot]);
  }

  Future<void> _teardownRun() async {
    _beepTimer?.cancel();
    _beepTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    for (final t in _parTimers) {
      t.cancel();
    }
    _parTimers.clear();
    await _detectionSub?.cancel();
    _detectionSub = null;
    await ref.read(shotDetectorProvider).stop();
    _clock.stop();
    if (await WakelockPlus.enabled) {
      await WakelockPlus.disable();
    }
    await BackgroundService.stop();
  }

  void _cleanup() {
    _beepTimer?.cancel();
    _tickTimer?.cancel();
    for (final t in _parTimers) {
      t.cancel();
    }
    _parTimers.clear();
    _detectionSub?.cancel();
    _detectionSub = null;
    _clock
      ..stop()
      ..reset();
    // Best-effort wakelock release; ignore failure.
    WakelockPlus.disable().catchError((_) {});
    BackgroundService.stop().catchError((_) {});
    final detector = ref.read(shotDetectorProvider);
    detector.stop().catchError((_) {});
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);
