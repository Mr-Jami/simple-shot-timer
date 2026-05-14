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

  int get shotCount => shots.length;

  int get totalTimeMs {
    if (shots.isEmpty) return 0;
    return shots.last.timeMs + penaltyMs;
  }

  int? get firstShotMs => shots.isEmpty ? null : shots.first.timeMs;

  List<int> get splitsMs {
    if (shots.length < 2) return const [];
    return [
      for (var i = 1; i < shots.length; i++)
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
        shots: shots,
      );
}
