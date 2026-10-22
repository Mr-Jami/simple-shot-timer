// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

/// Seeks a video while the user scrubs. Every seek is exact, so the player
/// decodes from the keyframe before it; seeking on every drag event starves
/// it and the picture stops moving (measured on the S21 FE). One seek at a
/// time, at least [minGap] apart and always to the latest position, keeps
/// the picture following; [release] then seeks to where the finger stopped.
class ThrottledSeeker {
  ThrottledSeeker(
    this._seek, {
    this.minGap = const Duration(milliseconds: 170),
  });

  final Future<void> Function(Duration position) _seek;
  final Duration minGap;

  Duration? _pending;
  var _releasing = false;
  Future<void>? _draining;
  Completer<void>? _gap;
  Timer? _gapTimer;

  /// Seeks towards [position] when the player is ready for it.
  void scrub(Duration position) {
    _pending = position;
    _draining ??= _drain();
  }

  /// Seeks to [position] as soon as the seek in flight is done, without the
  /// gap. Completes when the player has it.
  Future<void> release(Duration position) {
    _pending = position;
    _releasing = true;
    _endGap();
    return _draining ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final target = _pending!;
        _pending = null;
        final gap = _gap = Completer<void>();
        if (_releasing) {
          gap.complete();
        } else {
          _gapTimer = Timer(minGap, _endGap);
        }
        await Future.wait([_seek(target), gap.future]);
      }
    } finally {
      _endGap();
      _releasing = false;
      _draining = null;
    }
  }

  void _endGap() {
    _gapTimer?.cancel();
    final gap = _gap;
    if (gap != null && !gap.isCompleted) gap.complete();
  }
}
