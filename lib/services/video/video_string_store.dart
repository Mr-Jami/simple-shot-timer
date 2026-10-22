// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import '../../models/timer_string.dart';

/// Where the video editor saves its string. Separate from the timer's
/// `StringStore`, so the timer and its test fakes don't change.
abstract interface class VideoStringStore {
  /// Saves a new string and its shots, pruning history to [historyCap].
  Future<TimerString> insertString(TimerString s, {required int historyCap});

  /// Writes the editor's current state of an already saved string ([s] has
  /// an id) in one transaction: label, notes, penalty, START in the clip and
  /// the shots. A null label or note clears it.
  Future<void> updateVideoString(TimerString s);

  Future<void> deleteString(int id);
}
