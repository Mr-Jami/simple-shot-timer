// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import '../../models/shot.dart';
import '../../models/timer_string.dart';

/// How a marker got where it is.
enum ShotOrigin {
  /// Placed by the analyzer and untouched.
  detected,

  /// Placed by the analyzer, then moved by hand.
  moved,

  /// Added by hand.
  added,
}

/// One shot marker in the video editor, in clip time.
class EditShot {
  const EditShot({
    required this.id,
    required this.ms,
    required this.origin,
    this.detectedMs,
  });

  /// Stable for one editing session (selection, undo).
  final int id;

  /// Milliseconds from the start of the clip.
  final int ms;
  final ShotOrigin origin;

  /// Where the analyzer put it; null for added shots.
  final int? detectedMs;

  EditShot _at(int ms) => EditShot(
        id: id,
        ms: ms,
        origin:
            origin == ShotOrigin.added ? ShotOrigin.added : ShotOrigin.moved,
        detectedMs: detectedMs,
      );
}

/// The editor's markers, in clip milliseconds. Immutable: every edit returns
/// a new document, so undo is keeping the previous one.
///
/// Set START and Last shot never delete anything: shots before START or
/// after the last shot stay in the document, drawn dimmed, and only
/// [activeShots] count. A deleted detected shot leaves a tombstone, so a
/// sensitivity change never brings it back (see [reconcile]).
class MarkerDoc {
  const MarkerDoc({
    this.fromMs = 0,
    required this.toMs,
    this.startMs,
    this.startEdited = false,
    this.shots = const [],
    this.tombstones = const [],
    this.endMs,
    this.nextId = 0,
  });

  /// A fresh document from the analyzer: START (null when no beep was found)
  /// and the detected shots, in clip milliseconds.
  factory MarkerDoc.detected({
    int fromMs = 0,
    required int toMs,
    required int? startMs,
    required List<int> shotMs,
  }) {
    final sorted = [...shotMs]..sort();
    return MarkerDoc(
      fromMs: fromMs,
      toMs: toMs,
      startMs: startMs,
      shots: [
        for (var i = 0; i < sorted.length; i++)
          EditShot(
            id: i,
            ms: sorted[i],
            origin: ShotOrigin.detected,
            detectedMs: sorted[i],
          ),
      ],
      nextId: sorted.length,
    );
  }

  /// A saved video string, reopened with "Choose video again". Shots added
  /// or moved by hand come back as added; the rest as detected.
  factory MarkerDoc.fromSaved(
    TimerString string, {
    int fromMs = 0,
    required int toMs,
  }) {
    final start = string.videoStartMs ?? 0;
    final shots = <EditShot>[];
    for (final s in string.shots) {
      final ms = start + s.timeMs;
      shots.add(EditShot(
        id: shots.length,
        ms: ms,
        origin: s.manual ? ShotOrigin.added : ShotOrigin.detected,
        detectedMs: s.manual ? null : ms,
      ));
    }
    shots.sort((a, b) => a.ms.compareTo(b.ms));
    return MarkerDoc(
      fromMs: fromMs,
      toMs: toMs,
      startMs: start,
      startEdited: true,
      shots: shots,
      nextId: shots.length,
    );
  }

  /// The stretch markers can be placed in: the whole clip, or the part of
  /// a long one that was analysed.
  final int fromMs;
  final int toMs;

  /// START in clip milliseconds; null until the analyzer or the user sets it.
  final int? startMs;

  /// The user placed START; a sensitivity change keeps it.
  final bool startEdited;

  /// Every marker, sorted by time.
  final List<EditShot> shots;

  /// Detected times of deleted detected or moved shots.
  final List<int> tombstones;

  /// Set by Last shot: later shots don't count.
  final int? endMs;
  final int nextId;

  /// The string's shots: after START and up to the last shot.
  List<EditShot> get activeShots {
    final start = startMs;
    if (start == null) return const [];
    return [
      for (final s in shots)
        if (s.ms > start && (endMs == null || s.ms <= endMs!)) s,
    ];
  }

  /// The string's shots as saved: times from START, hand-placed ones manual.
  List<Shot> toShots() {
    final start = startMs ?? 0;
    final active = activeShots;
    return [
      for (var i = 0; i < active.length; i++)
        Shot(
          index: i,
          timeMs: active[i].ms - start,
          manual: active[i].origin != ShotOrigin.detected,
        ),
    ];
  }

  /// Ready to save: a START and at least one shot after it.
  bool get isComplete => startMs != null && activeShots.isNotEmpty;

  EditShot? shotById(int id) {
    for (final s in shots) {
      if (s.id == id) return s;
    }
    return null;
  }

  MarkerDoc setStart(int ms) => _copy(startMs: _clamp(ms), startEdited: true);

  /// Adds a shot at [ms] (its id is the current [nextId]). A shot past the
  /// last shot becomes the new last shot.
  MarkerDoc addShot(int ms) {
    final at = _clamp(ms);
    return _copy(
      shots: _sorted([
        ...shots,
        EditShot(id: nextId, ms: at, origin: ShotOrigin.added),
      ]),
      endMs: endMs != null && at > endMs! ? at : endMs,
      nextId: nextId + 1,
    );
  }

  /// Moves a shot; the end of the string goes with the shot marked Last
  /// shot.
  MarkerDoc moveShot(int id, int ms) {
    if (shotById(id) == null) return this;
    final at = _clamp(ms);
    return _copy(
      shots: _sorted([for (final s in shots) s.id == id ? s._at(at) : s]),
      endMs: endMs != null && shotById(id)?.ms == endMs ? at : null,
    );
  }

  MarkerDoc deleteShot(int id) {
    final shot = shotById(id);
    if (shot == null) return this;
    return _copy(
      shots: [
        for (final s in shots)
          if (s.id != id) s
      ],
      tombstones: [
        ...tombstones,
        if (shot.detectedMs != null) shot.detectedMs!,
      ],
    );
  }

  MarkerDoc setLastShot(int id) {
    final shot = shotById(id);
    return shot == null ? this : _copy(endMs: shot.ms);
  }

  /// Applies a new detection (another sensitivity) and keeps the user's
  /// edits: moved and added shots stay, untouched detected shots are
  /// replaced, and a detection near a tombstone or near a kept shot (moved
  /// shots by their detected time too) is dropped. START follows the new
  /// detection unless the user placed it or the new one found none.
  MarkerDoc reconcile({required int? startMs, required List<int> shotMs}) {
    const sameDetectionMs = 30;
    const keptShotMs = 50;
    final kept = [
      for (final s in shots)
        if (s.origin != ShotOrigin.detected) s
    ];
    bool near(int a, int b, int within) => (a - b).abs() <= within;
    var id = nextId;
    final fresh = <EditShot>[
      for (final ms in shotMs)
        if (!tombstones.any((t) => near(ms, t, sameDetectionMs)) &&
            !kept.any((k) =>
                near(ms, k.ms, keptShotMs) ||
                (k.detectedMs != null &&
                    near(ms, k.detectedMs!, sameDetectionMs))))
          EditShot(
              id: id++, ms: ms, origin: ShotOrigin.detected, detectedMs: ms),
    ];
    return _copy(
      startMs: startEdited ? this.startMs : startMs,
      shots: _sorted([...kept, ...fresh]),
      nextId: id,
    );
  }

  int _clamp(int ms) => ms.clamp(fromMs, toMs);

  static List<EditShot> _sorted(List<EditShot> shots) =>
      shots..sort((a, b) => a.ms.compareTo(b.ms));

  MarkerDoc _copy({
    int? startMs,
    bool? startEdited,
    List<EditShot>? shots,
    List<int>? tombstones,
    int? endMs,
    int? nextId,
  }) =>
      MarkerDoc(
        fromMs: fromMs,
        toMs: toMs,
        startMs: startMs ?? this.startMs,
        startEdited: startEdited ?? this.startEdited,
        shots: shots ?? this.shots,
        tombstones: tombstones ?? this.tombstones,
        endMs: endMs ?? this.endMs,
        nextId: nextId ?? this.nextId,
      );
}
