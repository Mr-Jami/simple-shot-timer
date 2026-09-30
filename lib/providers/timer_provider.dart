import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';
import '../models/par_config.dart';
import '../models/par_schedule.dart';
import '../models/shot.dart';
import '../models/timer_state.dart';
import '../models/timer_string.dart';
import 'history_provider.dart';
import 'providers.dart';
import 'settings_provider.dart';

class TimerNotifier extends Notifier<TimerState> {
  final Stopwatch _clock = Stopwatch();
  Timer? _beepTimer;
  Timer? _tickTimer;
  final List<Timer> _parTimers = [];
  StreamSubscription<int>? _detectionSub;
  StreamSubscription<int>? _beepOnsetSub;
  Timer? _onsetTimeoutTimer;

  /// Master-clock `t=0` for the current cycle. Shot timestamps and the on-screen
  /// elapsed counter are both measured from here, so each par cycle reads from
  /// 0. Initially provisional (set to the beep-playback request time plus the
  /// manual offset); once the detector reports the *audible* beep onset it is
  /// rebased onto that, correcting for audio output latency (issue #18).
  int _cycleStartClockMs = 0;

  /// Clock time at which the current cycle's beep playback was requested — the
  /// reference the measured onset latency is computed against.
  int _pendingBeepRequestedMs = 0;

  /// Whether we're still waiting for the audible onset of the current cycle's
  /// beep. Guards against acting on a stale/duplicate onset event.
  bool _awaitingOnset = false;

  /// Latency beyond which a measured onset is treated as a spurious match
  /// (noise, a late unrelated tone) and ignored — we keep the provisional base.
  static const int _maxPlausibleLatencyMs = 700;

  /// How long to wait for an onset before giving up for this cycle and keeping
  /// the provisional (request-time + manual offset) base.
  static const int _onsetTimeoutMs = 900;

  /// Currently-active par cycle (1..N). For non-par/single-cycle runs this
  /// stays at 1 throughout.
  int _currentCycle = 1;

  AppSettings _snapshot = const AppSettings();
  DrillMode _runMode = DrillMode.standard;
  DelayMode _runDelayMode = DelayMode.instant;

  /// Output latency (ms) the flash and haptic are delayed by so they land on
  /// the audible beep instead of on the playback request. Seeded from the
  /// persisted estimate at start and refined by every measured onset.
  int _latencyEstimateMs = AppSettings.defaultBeepLatencyEstimateMs;
  final List<Timer> _signalTimers = [];

  /// A finished run that detected nothing is kept here instead of being
  /// written to history; it is saved only if the user adds a shot by hand.
  TimerString? _pendingDraft;

  /// True while [start] or [stop] is in progress. Both await platform work
  /// before the phase changes, so a second tap in that window must be a
  /// no-op rather than a second run or a second history row.
  bool _busy = false;

  @override
  TimerState build() {
    ref.onDispose(_cleanup);
    return TimerState.idle();
  }

  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    try {
      await _start();
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    if (_busy) return;
    _busy = true;
    try {
      await _stop();
    } finally {
      _busy = false;
    }
  }

  Future<void> _start() async {
    if (state.phase != TimerPhase.idle && state.phase != TimerPhase.finished) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final detector = ref.read(shotSourceProvider);
    if (!await detector.hasPermission()) {
      // Set a translation key; the UI listener resolves it through
      // AppLocalizations so the SnackBar matches the current language.
      state = state.copyWith(error: 'errors.micPermissionDenied');
      return;
    }

    _snapshot = settings;
    _runMode = settings.drillMode;
    _runDelayMode = settings.delayMode;
    _latencyEstimateMs = settings.beepLatencyEstimateMs;
    _pendingDraft = null;
    final delayMs = _computeDelayMs(settings);

    final env = ref.read(runEnvironmentProvider);
    if (settings.keepScreenAwake) {
      await env.setKeepAwake(true);
    }
    await env.setForeground(true);

    // Reset clock but leave it stopped. We delay starting it until after the
    // native mic stream is ready, so the Timer(delayMs) below and the on-screen
    // countdown both measure from the same t=0.
    _clock
      ..stop()
      ..reset();

    // Show the countdown view immediately for instant feedback. elapsedMs stays
    // at 0 (clock not running yet), so the display reads the full delayMs until
    // the clock actually starts a few hundred ms later.
    // Carry the flash counter over: it only has to increase within the app
    // session, and dropping it to zero would read as a beep to the overlay.
    state = TimerState.idle().copyWith(
      phase: delayMs > 0 ? TimerPhase.countdown : TimerPhase.running,
      delayUsedMs: delayMs,
      flashTick: state.flashTick,
      clearError: true,
      clearSavedId: true,
    );
    // Not awaited: the countdown must be on screen in the same frame as the
    // tap, and the check only decides whether a one-line notice is shown.
    unawaited(_checkBeepAudible());

    // Subscribe to detections first so the stream is ready when the beep fires.
    _detectionSub = detector.events.listen(_onDetection);
    // And to beep-onset events, so we can rebase t=0 onto the audible beep.
    _beepOnsetSub = detector.beepOnsetEvents.listen(_onBeepOnset);
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

  Future<void> _stop() async {
    if (state.phase != TimerPhase.countdown &&
        state.phase != TimerPhase.running) {
      return;
    }
    await _teardownRun();

    final shots = List<Shot>.from(state.shots);
    if (shots.isEmpty && state.phase == TimerPhase.countdown) {
      // Stopped before the start beep fired — discard.
      state = _idleKeepingCounter();
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

    if (shots.isEmpty) {
      // Nothing to review and nothing worth a history row. Keep the draft so
      // "Add shot" from the finished view can still save it.
      _pendingDraft = draft;
      state = state.copyWith(
        phase: TimerPhase.finished,
        shots: const [],
        clearSavedId: true,
      );
      return;
    }

    try {
      final saved = await ref
          .read(stringStoreProvider)
          .insertString(draft, historyCap: settings.historyCap);
      state = state.copyWith(
        phase: TimerPhase.finished,
        shots: saved.shots,
        savedStringId: saved.id,
        savedAt: saved.createdAt,
      );
      ref.invalidate(historyProvider);
    } catch (_) {
      // Keep the result on screen; the next "Add shot" retries the save.
      _pendingDraft = draft;
      state = state.copyWith(
        phase: TimerPhase.finished,
        shots: shots,
        clearSavedId: true,
        error: 'errors.saveFailed',
      );
    }
  }

  void reset() {
    _cleanup();
    _pendingDraft = null;
    state = _idleKeepingCounter();
  }

  /// Back to idle when the run is over and the result has been seen. A no-op
  /// while a string is in progress, so leaving Home mid-run is safe.
  void resetIfFinished() {
    if (state.phase == TimerPhase.finished) reset();
  }

  TimerState _idleKeepingCounter() =>
      TimerState.idle().copyWith(flashTick: state.flashTick);

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
    if (state.phase != TimerPhase.finished) return;
    final store = ref.read(stringStoreProvider);
    final id = state.savedStringId;
    if (id != null) {
      await store.replaceShots(id, updated);
      ref.invalidate(historyProvider);
      return;
    }
    // First shot on a run that detected nothing: now it is worth saving.
    final draft = _pendingDraft;
    // Null here means a save is already in flight; the shot is in state and
    // the in-flight save reconciles it below.
    if (draft == null) return;
    _pendingDraft = null; // before the await: a second tap must not insert it
    try {
      final saved = await store.insertString(
        draft.copyWith(shots: updated),
        historyCap: _snapshot.historyCap,
      );
      if (state.phase != TimerPhase.finished) {
        // Reset while saving; the row exists, the screen has moved on.
        ref.invalidate(historyProvider);
        return;
      }
      // Shots added or removed while saving live only in state. Make the
      // row match state rather than the other way round.
      final current = state.shots;
      if (current.length == saved.shots.length) {
        state = state.copyWith(
          shots: saved.shots,
          savedStringId: saved.id,
          savedAt: saved.createdAt,
        );
      } else {
        final reindexed = [
          for (var i = 0; i < current.length; i++)
            current[i].copyWith(index: i, stringId: saved.id),
        ];
        await store.replaceShots(saved.id!, reindexed);
        state = state.copyWith(
          shots: reindexed,
          savedStringId: saved.id,
          savedAt: saved.createdAt,
        );
      }
      ref.invalidate(historyProvider);
    } catch (_) {
      _pendingDraft = draft;
      state = state.copyWith(error: 'errors.saveFailed');
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
          .read(stringStoreProvider)
          .replaceShots(state.savedStringId!, reindexed);
      ref.invalidate(historyProvider);
    }
  }

  Future<void> updateNotes(String notes) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref.read(stringStoreProvider).updateStringMeta(id, notes: notes);
    ref.invalidate(historyProvider);
  }

  Future<void> updateLabel(String label) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref.read(stringStoreProvider).updateStringMeta(id, label: label);
    ref.invalidate(historyProvider);
  }

  Future<void> updatePenalty(int penaltyMs) async {
    final id = state.savedStringId;
    if (id == null) return;
    await ref
        .read(stringStoreProvider)
        .updateStringMeta(id, penaltyMs: penaltyMs);
    ref.invalidate(historyProvider);
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
    state = state.copyWith(phase: TimerPhase.running);
    if (!silent) {
      await _playStartBeep();
      _scheduleSignals();
    }
    _schedulePars();
    _startTick();
  }

  /// The flash and the haptic are the beep's visual and tactile twins. Both
  /// are delayed by the current output-latency estimate so all three land on
  /// the same instant; the acoustic onset keeps the estimate honest.
  void _scheduleSignals() {
    _signalTimers.add(
      Timer(Duration(milliseconds: _latencyEstimateMs), () {
        if (state.phase != TimerPhase.running &&
            state.phase != TimerPhase.countdown) {
          return;
        }
        state = state.copyWith(flashTick: state.flashTick + 1);
        unawaited(_maybeHaptic());
      }),
    );
  }

  /// Exponential moving average of the output latency: 70% history, 30% new
  /// sample, so two or three strings converge on a phone and output route
  /// without one odd reading dragging the estimate around.
  static int blendLatency(int estimateMs, int measuredMs) =>
      (0.7 * estimateMs + 0.3 * measuredMs).round();

  Future<void> _checkBeepAudible() async {
    final audible = await ref.read(volumeServiceProvider).isMediaAudible();
    if (audible != false) return;
    if (state.phase != TimerPhase.countdown &&
        state.phase != TimerPhase.running) {
      return;
    }
    state = state.copyWith(beepInaudible: true);
  }

  /// Marks the start of a new par cycle: resets the per-cycle clock + state
  /// so shot timestamps and the on-screen elapsed counter both read from 0.
  ///
  /// The base starts *provisional* — anchored to the playback request time plus
  /// the manual offset — and is rebased onto the audible beep by [_onBeepOnset]
  /// once the detector hears it.
  void _beginCycle(int cycle) {
    _currentCycle = cycle;
    _pendingBeepRequestedMs = _clock.elapsedMilliseconds;
    _cycleStartClockMs =
        _pendingBeepRequestedMs + _snapshot.audioLatencyOffsetMs;
    _armOnsetDetection();
    state = state.copyWith(
      elapsedMs: 0,
      currentParIndex: cycle,
    );
  }

  /// Arms acoustic beep-onset detection for the cycle just started, with a
  /// timeout that falls back to the provisional base if no onset is heard
  /// (e.g. beep muted, or output route the mic can't pick up).
  void _armOnsetDetection() {
    _awaitingOnset = true;
    final detector = ref.read(shotSourceProvider);
    detector.armBeepDetection();
    _onsetTimeoutTimer?.cancel();
    _onsetTimeoutTimer = Timer(
      const Duration(milliseconds: _onsetTimeoutMs),
      () {
        _awaitingOnset = false;
        ref.read(shotSourceProvider).cancelBeepDetection();
      },
    );
  }

  /// Rebases the current cycle's `t=0` onto the moment the beep became audible.
  /// Already-recorded shots in this cycle are shifted by the same correction so
  /// nothing reads inconsistently, and the elapsed display is refreshed.
  void _onBeepOnset(int onsetMs) {
    if (!_awaitingOnset) return;
    final result = calibrateBase(
      requestMs: _pendingBeepRequestedMs,
      onsetMs: onsetMs,
      manualOffsetMs: _snapshot.audioLatencyOffsetMs,
      maxPlausibleLatencyMs: _maxPlausibleLatencyMs,
    );
    _awaitingOnset = false;
    _onsetTimeoutTimer?.cancel();
    if (result == null) return; // implausible — keep the provisional base

    _latencyEstimateMs = blendLatency(_latencyEstimateMs, result.latencyMs);

    final delta = result.newBaseMs - _cycleStartClockMs;
    if (delta == 0) return;
    _cycleStartClockMs = result.newBaseMs;
    final adjusted = [
      for (final s in state.shots)
        if (s.cycleIndex == _currentCycle)
          s.copyWith(timeMs: math.max(0, s.timeMs - delta))
        else
          s,
    ];
    state = state.copyWith(
      shots: adjusted,
      elapsedMs: math.max(0, _clock.elapsedMilliseconds - _cycleStartClockMs),
    );
  }

  /// Pure latency-calibration math (visible for testing). Given when the beep
  /// was requested and when it was actually heard, returns the corrected base
  /// (audible onset + manual offset), or null when the measured latency is out
  /// of the plausible range and should be discarded.
  static ({int newBaseMs, int latencyMs})? calibrateBase({
    required int requestMs,
    required int onsetMs,
    required int manualOffsetMs,
    required int maxPlausibleLatencyMs,
  }) {
    final latencyMs = onsetMs - requestMs;
    if (latencyMs < 0 || latencyMs > maxPlausibleLatencyMs) return null;
    return (newBaseMs: onsetMs + manualOffsetMs, latencyMs: latencyMs);
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
        state = state.copyWith(currentParIndex: event.cycle);
        if (event.kind == ParBeepKind.start) {
          _playStartBeep();
        } else {
          _playParBeep();
        }
        _scheduleSignals();
      }));
    }
  }

  Future<void> _playStartBeep() async {
    final audio = ref.read(beepPlayerProvider);
    unawaited(audio.playStartBeep(volume: _snapshot.beepVolume));
  }

  Future<void> _playParBeep() async {
    final audio = ref.read(beepPlayerProvider);
    unawaited(audio.playParBeep(volume: _snapshot.beepVolume));
  }

  Future<void> _maybeHaptic() async {
    if (!_snapshot.hapticOnBeep) return;
    await ref.read(runEnvironmentProvider).vibrate();
  }

  void _startTick() {
    _tickTimer?.cancel();
    final detector = ref.read(shotSourceProvider);
    _tickTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (state.phase != TimerPhase.running &&
          state.phase != TimerPhase.countdown) {
        return;
      }
      state = state.copyWith(
        elapsedMs: math.max(0, _clock.elapsedMilliseconds - _cycleStartClockMs),
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
    _onsetTimeoutTimer?.cancel();
    _onsetTimeoutTimer = null;
    _awaitingOnset = false;
    for (final t in _parTimers) {
      t.cancel();
    }
    _parTimers.clear();
    _cancelSignalTimers();
    if (_latencyEstimateMs != _snapshot.beepLatencyEstimateMs) {
      // Persist what this run learned about the output route, once.
      unawaited(ref.read(settingsProvider.notifier).update(
        (c) => c.copyWith(beepLatencyEstimateMs: _latencyEstimateMs),
      ));
    }
    // Not awaited: nothing depends on the cancel completing, and a broadcast
    // subscription's cancel future resolves outside the caller's zone.
    unawaited(_detectionSub?.cancel());
    _detectionSub = null;
    unawaited(_beepOnsetSub?.cancel());
    _beepOnsetSub = null;
    await ref.read(shotSourceProvider).stop();
    _clock.stop();
    final env = ref.read(runEnvironmentProvider);
    await env.setKeepAwake(false);
    await env.setForeground(false);
  }

  void _cancelSignalTimers() {
    for (final t in _signalTimers) {
      t.cancel();
    }
    _signalTimers.clear();
  }

  void _cleanup() {
    _beepTimer?.cancel();
    _tickTimer?.cancel();
    _onsetTimeoutTimer?.cancel();
    _onsetTimeoutTimer = null;
    _awaitingOnset = false;
    for (final t in _parTimers) {
      t.cancel();
    }
    _parTimers.clear();
    _cancelSignalTimers();
    _detectionSub?.cancel();
    _detectionSub = null;
    _beepOnsetSub?.cancel();
    _beepOnsetSub = null;
    _clock
      ..stop()
      ..reset();
    // Best-effort release of everything the run held; ignore failures.
    final env = ref.read(runEnvironmentProvider);
    env.setKeepAwake(false).catchError((_) {});
    env.setForeground(false).catchError((_) {});
    ref.read(shotSourceProvider).stop().catchError((_) {});
  }
}

final timerProvider = NotifierProvider<TimerNotifier, TimerState>(
  TimerNotifier.new,
);
