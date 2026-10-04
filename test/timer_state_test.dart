// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_state.dart';

void main() {
  group('TimerState.nothingRecorded', () {
    test('is true only for a finished, empty, unsaved run', () {
      final finishedEmpty =
          TimerState.idle().copyWith(phase: TimerPhase.finished);
      expect(finishedEmpty.nothingRecorded, isTrue);

      expect(
        finishedEmpty.copyWith(savedStringId: 4).nothingRecorded,
        isFalse,
        reason: 'a saved string is a result, even if shots were removed',
      );
      expect(
        finishedEmpty.copyWith(shots: [
          Shot(index: 0, timeMs: 1250, cycleIndex: 1),
        ]).nothingRecorded,
        isFalse,
      );
      expect(
        TimerState.idle().copyWith(phase: TimerPhase.running).nothingRecorded,
        isFalse,
      );
    });
  });

  group('TimerState.copyWith', () {
    test('clearSavedId also clears the saved time', () {
      final saved = TimerState.idle().copyWith(
        phase: TimerPhase.finished,
        savedStringId: 9,
        savedAt: DateTime(2026, 9, 30, 23, 24),
      );
      final cleared = saved.copyWith(clearSavedId: true);
      expect(cleared.savedStringId, isNull);
      expect(cleared.savedAt, isNull);
    });

    test('beepInaudible defaults to false and survives copies', () {
      expect(TimerState.idle().beepInaudible, isFalse);
      final flagged = TimerState.idle().copyWith(beepInaudible: true);
      expect(flagged.copyWith(elapsedMs: 5).beepInaudible, isTrue);
    });
  });
}
