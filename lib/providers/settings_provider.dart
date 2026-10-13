// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/drill_config.dart';
import 'providers.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.read(settingsServiceProvider).load();
  }

  Future<void> update(AppSettings Function(AppSettings) updater) async {
    final next = updater(state);
    state = next;
    await ref.read(settingsServiceProvider).save(next);
  }

  /// Loads a saved drill: only the drill-configuration fields change, every
  /// other setting keeps its value (issue #24).
  Future<void> applyDrill(DrillConfig config) => update(config.applyTo);

  /// "Reset settings only": defaults again, custom drills kept.
  Future<void> reset() async {
    await ref.read(settingsServiceProvider).reset();
    state = const AppSettings();
  }

  /// Preferences half of "Delete all data and settings": defaults again and
  /// the custom drills gone too. The caller deletes the saved strings and
  /// invalidates `customDrillsProvider`, which still holds the old list.
  /// False when the prefs write failed; the state is left alone then, since
  /// the old settings would be back on the next launch.
  Future<bool> deleteAll() async {
    final cleared = await ref.read(settingsServiceProvider).clear();
    if (cleared) state = const AppSettings();
    return cleared;
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
