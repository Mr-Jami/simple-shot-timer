import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_string.dart';
import 'providers.dart';

class HistoryNotifier extends AsyncNotifier<List<TimerString>> {
  @override
  Future<List<TimerString>> build() async {
    return ref.read(databaseProvider).listStrings();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).listStrings(),
    );
  }

  Future<void> delete(int id) async {
    await ref.read(databaseProvider).deleteString(id);
    await refresh();
  }

  Future<void> deleteAll() async {
    await ref.read(databaseProvider).deleteAll();
    await refresh();
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<TimerString>>(
  HistoryNotifier.new,
);
