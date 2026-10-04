// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:convert';

import 'drill_config.dart';

/// A user-named, saved [DrillConfig] (issue #24).
class CustomDrill {
  const CustomDrill({
    required this.id,
    required this.name,
    required this.config,
  });

  /// Throws [FormatException] on a missing id or blank name; [decodeList]
  /// turns that into "skip this entry".
  factory CustomDrill.fromMap(Map<String, Object?> map) {
    final id = map['id'];
    if (id is! int) throw const FormatException('custom drill without id');
    final rawName = map['name'];
    final name = normalizeName(rawName is String ? rawName : '');
    if (name.isEmpty) throw const FormatException('custom drill without name');
    return CustomDrill(id: id, name: name, config: DrillConfig.fromMap(map));
  }

  /// Longest name the entry dialog accepts; keeps the home chip readable.
  static const int maxNameLength = 40;

  /// Stable identity used to target rename/overwrite/delete. Assigned by the
  /// notifier as max(existing ids) + 1 and never shown to the user.
  final int id;
  final String name;
  final DrillConfig config;

  CustomDrill copyWith({String? name, DrillConfig? config}) => CustomDrill(
        id: id,
        name: name ?? this.name,
        config: config ?? this.config,
      );

  /// Trims and collapses inner whitespace so "  Bill   Drill " is stored as
  /// "Bill Drill".
  static String normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Case-insensitive comparison of normalized names: "bill drill" and
  /// "Bill Drill" are the same drill.
  static bool sameName(String a, String b) =>
      normalizeName(a).toLowerCase() == normalizeName(b).toLowerCase();

  /// Flat map: `id`, `name` plus the [DrillConfig] keys.
  Map<String, Object?> toMap() => {'id': id, 'name': name, ...config.toMap()};

  static String encodeList(List<CustomDrill> drills) =>
      jsonEncode([for (final d in drills) d.toMap()]);

  /// Never throws. A corrupt blob yields an empty list and a corrupt entry is
  /// skipped, so a bad prefs value can't take the app down at startup.
  static List<CustomDrill> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    final Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (raw is! List) return const [];
    final drills = <CustomDrill>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        drills.add(CustomDrill.fromMap(Map<String, Object?>.from(entry)));
      } on FormatException {
        continue;
      }
    }
    return drills;
  }
}
