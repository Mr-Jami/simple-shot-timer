class Shot {
  Shot({
    this.id,
    this.stringId,
    required this.index,
    required this.timeMs,
    this.manual = false,
  });

  final int? id;
  final int? stringId;
  final int index;
  final int timeMs;
  final bool manual;

  double get timeSeconds => timeMs / 1000.0;

  Shot copyWith({
    int? id,
    int? stringId,
    int? index,
    int? timeMs,
    bool? manual,
  }) =>
      Shot(
        id: id ?? this.id,
        stringId: stringId ?? this.stringId,
        index: index ?? this.index,
        timeMs: timeMs ?? this.timeMs,
        manual: manual ?? this.manual,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'string_id': stringId,
        'idx': index,
        'time_ms': timeMs,
        'manual': manual ? 1 : 0,
      };

  factory Shot.fromMap(Map<String, Object?> map) => Shot(
        id: map['id'] as int?,
        stringId: map['string_id'] as int?,
        index: map['idx'] as int,
        timeMs: map['time_ms'] as int,
        manual: (map['manual'] as int? ?? 0) == 1,
      );
}
