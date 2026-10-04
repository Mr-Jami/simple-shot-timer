// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:convert';

class ParConfig {
  const ParConfig({
    required this.enabled,
    required this.durationMs,
  });

  final bool enabled;
  final int durationMs;

  double get durationSeconds => durationMs / 1000.0;

  ParConfig copyWith({bool? enabled, int? durationMs}) => ParConfig(
        enabled: enabled ?? this.enabled,
        durationMs: durationMs ?? this.durationMs,
      );

  Map<String, Object?> toMap() => {
        'enabled': enabled,
        'duration_ms': durationMs,
      };

  factory ParConfig.fromMap(Map<String, Object?> map) => ParConfig(
        enabled: map['enabled'] as bool? ?? false,
        durationMs: map['duration_ms'] as int? ?? 2000,
      );

  static String encodeList(List<ParConfig> pars) =>
      jsonEncode(pars.map((p) => p.toMap()).toList());

  static List<ParConfig> decodeList(String? json) {
    if (json == null || json.isEmpty) {
      return const [];
    }
    final raw = jsonDecode(json) as List<dynamic>;
    return raw
        .map((e) => ParConfig.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
  }
}
