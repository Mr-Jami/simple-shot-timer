import 'enums.dart';
import 'par_config.dart';
import 'shot.dart';

class TimerString {
  TimerString({
    this.id,
    required this.createdAt,
    required this.drillMode,
    required this.delayMode,
    required this.delayUsedMs,
    required this.pars,
    required this.shots,
    this.label,
    this.notes,
    this.penaltyMs = 0,
    this.parRepeatCount,
    this.parIntervalMs,
  });

  final int? id;
  final DateTime createdAt;
  final DrillMode drillMode;
  final DelayMode delayMode;
  final int delayUsedMs;
  final List<ParConfig> pars;
  final List<Shot> shots;
  final String? label;
  final String? notes;
  final int penaltyMs;

  /// Number of par cycles configured for this run. Only meaningful when
  /// [drillMode] is [DrillMode.par]; null for older saved strings and for
  /// other drill modes.
  final int? parRepeatCount;

  /// Rest interval (ms) between par cycles. Null for non-par or pre-v3 rows.
  final int? parIntervalMs;

  int get shotCount => shots.length;

  int get totalTimeMs {
    if (shots.isEmpty) return 0;
    return shots.last.timeMs + penaltyMs;
  }

  int? get firstShotMs => shots.isEmpty ? null : shots.first.timeMs;

  /// Within-cycle splits only — never crosses a cycle boundary because shot
  /// times restart from zero at each par cycle, so a naive subtraction across
  /// cycles would produce a negative split.
  List<int> get splitsMs {
    if (shots.length < 2) return const [];
    return [
      for (var i = 1; i < shots.length; i++)
        if (shots[i].cycleIndex == shots[i - 1].cycleIndex)
          shots[i].timeMs - shots[i - 1].timeMs,
    ];
  }

  int? get fastestSplitMs {
    final s = splitsMs;
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a < b ? a : b);
  }

  int? get slowestSplitMs {
    final s = splitsMs;
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a > b ? a : b);
  }

  int? get averageSplitMs {
    final s = splitsMs;
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a + b) ~/ s.length;
  }

  /// Distinct cycle indices that have at least one shot, ordered ascending.
  /// Always returns at least `[1]` for a non-par run with shots; empty if no
  /// shots were captured.
  List<int> get cyclesWithShots {
    final seen = <int>{};
    for (final s in shots) {
      seen.add(s.cycleIndex);
    }
    final list = seen.toList()..sort();
    return list;
  }

  /// Shots that belong to [cycle], in order.
  List<Shot> shotsForCycle(int cycle) =>
      [for (final s in shots) if (s.cycleIndex == cycle) s];

  /// Splits within [cycle]. Uses cycle-relative timeMs which is what shots
  /// already carry, so no extra arithmetic needed.
  List<int> splitsForCycle(int cycle) {
    final cs = shotsForCycle(cycle);
    if (cs.length < 2) return const [];
    return [
      for (var i = 1; i < cs.length; i++) cs[i].timeMs - cs[i - 1].timeMs,
    ];
  }

  /// Time of the last shot in [cycle] (i.e. how long the cycle took).
  /// Returns null when the cycle has no shots.
  int? totalForCycle(int cycle) {
    final cs = shotsForCycle(cycle);
    if (cs.isEmpty) return null;
    return cs.last.timeMs;
  }

  /// Time of the first shot in [cycle]. Returns null when empty.
  int? firstShotForCycle(int cycle) {
    final cs = shotsForCycle(cycle);
    if (cs.isEmpty) return null;
    return cs.first.timeMs;
  }

  TimerString copyWith({
    int? id,
    DateTime? createdAt,
    DrillMode? drillMode,
    DelayMode? delayMode,
    int? delayUsedMs,
    List<ParConfig>? pars,
    List<Shot>? shots,
    String? label,
    String? notes,
    int? penaltyMs,
    int? parRepeatCount,
    int? parIntervalMs,
  }) =>
      TimerString(
        id: id ?? this.id,
        createdAt: createdAt ?? this.createdAt,
        drillMode: drillMode ?? this.drillMode,
        delayMode: delayMode ?? this.delayMode,
        delayUsedMs: delayUsedMs ?? this.delayUsedMs,
        pars: pars ?? this.pars,
        shots: shots ?? this.shots,
        label: label ?? this.label,
        notes: notes ?? this.notes,
        penaltyMs: penaltyMs ?? this.penaltyMs,
        parRepeatCount: parRepeatCount ?? this.parRepeatCount,
        parIntervalMs: parIntervalMs ?? this.parIntervalMs,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'drill_mode': drillMode.name,
        'delay_mode': delayMode.name,
        'delay_used_ms': delayUsedMs,
        'pars_json': ParConfig.encodeList(pars),
        'label': label,
        'notes': notes,
        'penalty_ms': penaltyMs,
        'par_repeat_count': parRepeatCount,
        'par_interval_ms': parIntervalMs,
      };

  factory TimerString.fromMap(
    Map<String, Object?> map, {
    List<Shot> shots = const [],
  }) =>
      TimerString(
        id: map['id'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
        drillMode: DrillMode.values.firstWhere(
          (e) => e.name == map['drill_mode'],
          orElse: () => DrillMode.standard,
        ),
        delayMode: DelayMode.values.firstWhere(
          (e) => e.name == map['delay_mode'],
          orElse: () => DelayMode.random,
        ),
        delayUsedMs: map['delay_used_ms'] as int? ?? 0,
        pars: ParConfig.decodeList(map['pars_json'] as String?),
        label: map['label'] as String?,
        notes: map['notes'] as String?,
        penaltyMs: map['penalty_ms'] as int? ?? 0,
        parRepeatCount: map['par_repeat_count'] as int?,
        parIntervalMs: map['par_interval_ms'] as int?,
        shots: shots,
      );
}
