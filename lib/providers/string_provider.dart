import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_string.dart';
import 'providers.dart';

final stringByIdProvider =
    FutureProvider.family<TimerString?, int>((ref, id) async {
  return ref.read(databaseProvider).getString(id);
});
