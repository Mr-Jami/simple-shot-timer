import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
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

  Future<void> reset() async {
    await ref.read(settingsServiceProvider).reset();
    state = const AppSettings();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
