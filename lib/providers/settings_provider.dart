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

  Future<void> reset() async {
    await ref.read(settingsServiceProvider).reset();
    state = const AppSettings();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
