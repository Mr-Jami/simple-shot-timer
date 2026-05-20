class Shot {
  Shot({
    this.id,
    this.stringId,
    required this.index,
    required this.timeMs,
    this.manual = false,
    this.cycleIndex = 1,
  });

  final int? id;
  final int? stringId;
  final int index;

  /// Time in ms measured from the start of [cycleIndex]. For non-par modes
  /// (standard, stage) and single-cycle par runs, this is just elapsed since
  /// the master start beep.
  final int timeMs;
  final bool manual;

  /// 1-based cycle this shot belongs to. Always 1 for non-par modes; in par
  /// mode with repeats, increments at each par-cycle boundary.
  final int cycleIndex;

  double get timeSeconds => timeMs / 1000.0;

  Shot copyWith({
    int? id,
    int? stringId,
    int? index,
    int? timeMs,
    bool? manual,
    int? cycleIndex,
  }) =>
      Shot(
        id: id ?? this.id,
        stringId: stringId ?? this.stringId,
        index: index ?? this.index,
        timeMs: timeMs ?? this.timeMs,
        manual: manual ?? this.manual,
        cycleIndex: cycleIndex ?? this.cycleIndex,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'string_id': stringId,
        'idx': index,
        'time_ms': timeMs,
        'manual': manual ? 1 : 0,
        'cycle_index': cycleIndex,
      };

  factory Shot.fromMap(Map<String, Object?> map) => Shot(
        id: map['id'] as int?,
        stringId: map['string_id'] as int?,
        index: map['idx'] as int,
        timeMs: map['time_ms'] as int,
        manual: (map['manual'] as int? ?? 0) == 1,
        cycleIndex: map['cycle_index'] as int? ?? 1,
      );
}
