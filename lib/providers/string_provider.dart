// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/timer_string.dart';
import 'providers.dart';

final stringByIdProvider =
    FutureProvider.family<TimerString?, int>((ref, id) async {
  return ref.read(databaseProvider).getString(id);
});
