import 'enums.dart';
import 'shot.dart';

class TimerState {
  const TimerState({
    required this.phase,
    required this.elapsedMs,
    required this.shots,
    required this.currentParIndex,
    required this.flashTick,
    this.micLevel = 0,
    this.delayUsedMs,
    this.savedStringId,
    this.error,
  });

  factory TimerState.idle() => const TimerState(
        phase: TimerPhase.idle,
        elapsedMs: 0,
        shots: [],
        currentParIndex: 0,
        flashTick: 0,
      );

  final TimerPhase phase;
  final int elapsedMs;
  final List<Shot> shots;
  final int currentParIndex;
  final double micLevel;

  /// Incremented every time a beep (start or par) fires so the UI can
  /// drive a one-shot flash animation by listening for changes.
  final int flashTick;

  final int? delayUsedMs;
  final int? savedStringId;
  final String? error;

  int get shotCount => shots.length;
  Shot? get lastShot => shots.isEmpty ? null : shots.last;
  int? get firstShotMs => shots.isEmpty ? null : shots.first.timeMs;
  int? get lastSplitMs {
    if (shots.length < 2) return null;
    return shots.last.timeMs - shots[shots.length - 2].timeMs;
  }

  TimerState copyWith({
    TimerPhase? phase,
    int? elapsedMs,
    List<Shot>? shots,
    int? currentParIndex,
    int? flashTick,
    double? micLevel,
    int? delayUsedMs,
    int? savedStringId,
    String? error,
    bool clearError = false,
    bool clearSavedId = false,
  }) =>
      TimerState(
        phase: phase ?? this.phase,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        shots: shots ?? this.shots,
        currentParIndex: currentParIndex ?? this.currentParIndex,
        flashTick: flashTick ?? this.flashTick,
        micLevel: micLevel ?? this.micLevel,
        delayUsedMs: delayUsedMs ?? this.delayUsedMs,
        savedStringId: clearSavedId ? null : (savedStringId ?? this.savedStringId),
        error: clearError ? null : (error ?? this.error),
      );
}
