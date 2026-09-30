import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_drill.dart';
import '../models/drill_config.dart';
import 'providers.dart';
import 'settings_provider.dart';

/// Saved custom drills in creation order (issue #24). State is updated
/// before the prefs write completes, mirroring [SettingsNotifier.update].
class CustomDrillsNotifier extends Notifier<List<CustomDrill>> {
  @override
  List<CustomDrill> build() => ref.read(settingsServiceProvider).loadDrills();

  Future<void> _persist(List<CustomDrill> next) async {
    state = next;
    await ref.read(settingsServiceProvider).saveDrills(next);
  }

  int get _nextId => state.fold(0, (max, d) => math.max(max, d.id)) + 1;

  /// First drill named [name] (trimmed, case-insensitive), or null.
  /// [excludeId] lets a rename ignore the drill being renamed.
  CustomDrill? findByName(String name, {int? excludeId}) {
    for (final d in state) {
      if (d.id != excludeId && CustomDrill.sameName(d.name, name)) return d;
    }
    return null;
  }

  /// Appends a new drill under the normalized [name]; a blank name is
  /// ignored rather than stored (the decoder would drop it anyway).
  Future<void> add(String name, DrillConfig config) async {
    final normalized = CustomDrill.normalizeName(name);
    if (normalized.isEmpty) return;
    await _persist([
      ...state,
      CustomDrill(id: _nextId, name: normalized, config: config),
    ]);
  }

  Future<void> rename(int id, String name) async {
    final normalized = CustomDrill.normalizeName(name);
    if (normalized.isEmpty) return;
    await _persist([
      for (final d in state) d.id == id ? d.copyWith(name: normalized) : d,
    ]);
  }

  /// Replaces the drill's configuration, keeping id, name and position.
  Future<void> overwrite(int id, DrillConfig config) => _persist([
        for (final d in state) d.id == id ? d.copyWith(config: config) : d,
      ]);

  Future<void> delete(int id) =>
      _persist([for (final d in state) if (d.id != id) d]);
}

final customDrillsProvider =
    NotifierProvider<CustomDrillsNotifier, List<CustomDrill>>(
  CustomDrillsNotifier.new,
);

/// The saved drill whose configuration equals the current settings, or null
/// once the user tweaks any drill value (or has saved nothing). Derived, not
/// stored, so it can never go stale. First match in creation order wins when
/// two drills share a configuration.
final activeDrillProvider = Provider<CustomDrill?>((ref) {
  final current = ref.watch(settingsProvider.select(DrillConfig.fromSettings));
  for (final d in ref.watch(customDrillsProvider)) {
    if (d.config == current) return d;
  }
  return null;
});
