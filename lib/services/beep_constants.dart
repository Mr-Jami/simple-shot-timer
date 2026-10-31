// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

/// The start and par beeps the app plays: a piezo-style tone in the ~2.3 kHz
/// range used by most club shot timers. The start beep is short; the par (end)
/// beep is longer so shooters can tell them apart without watching the screen.
///
/// Kept apart from `AudioService`, which pulls in the audioplayers plugin, so
/// the offline clip analyzer can recognise these beeps in a recording while
/// staying pure Dart.
abstract final class Beeps {
  static const int frequencyHz = 2325;
  static const int startDurationMs = 300;
  static const int parDurationMs = 700;
}
