// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import '../../models/shot.dart';
import '../../models/timer_string.dart';
import 'clip_analyzer.dart' show ShotSensitivity;

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
    this.detectedMs,
  });

  /// Stable for one editing session (selection, undo).
  final int id;

  /// Milliseconds from the start of the clip.
  final int ms;

  /// Where the analyzer put it; null for added shots.
  final int? detectedMs;

  /// From the times: a shot dragged back onto where it was detected is
  /// detected again.
  ShotOrigin get origin => detectedMs == null
      ? ShotOrigin.added
      : ms == detectedMs
          ? ShotOrigin.detected
          : ShotOrigin.moved;

  EditShot _at(int ms) => EditShot(id: id, ms: ms, detectedMs: detectedMs);
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
    this.lastShotId,
    this.nextId = 0,
    this.sensitivity = ShotSensitivity.normal,
  });

  /// A fresh document from the analyzer at [sensitivity]: START (null when
  /// no beep was found) and the detected shots, in clip milliseconds.
  factory MarkerDoc.detected({
    int fromMs = 0,
    required int toMs,
    required int? startMs,
    required List<int> shotMs,
    ShotSensitivity sensitivity = ShotSensitivity.normal,
  }) {
    final sorted = [...shotMs]..sort();
    return MarkerDoc(
      fromMs: fromMs,
      toMs: toMs,
      startMs: startMs,
      shots: [
        for (var i = 0; i < sorted.length; i++)
          EditShot(id: i, ms: sorted[i], detectedMs: sorted[i]),
      ],
      nextId: sorted.length,
      sensitivity: sensitivity,
    );
  }

  /// A saved video string, reopened with "Choose video again". Shots added
  /// or moved by hand come back as added; the rest as detected. Only
  /// markers inside [fromMs]..[toMs] come back, since another video can be
  /// opened anyway: without its START the editor asks for one, as for a
  /// clip with no beep.
  factory MarkerDoc.fromSaved(
    TimerString string, {
    int fromMs = 0,
    required int toMs,
  }) {
    bool inside(int ms) => ms >= fromMs && ms <= toMs;
    final start = string.videoStartMs;
    final shots = <EditShot>[];
    if (start != null) {
      for (final s in string.shots) {
        final ms = start + s.timeMs;
        if (!inside(ms)) continue;
        shots.add(EditShot(
          id: shots.length,
          ms: ms,
          detectedMs: s.manual ? null : ms,
        ));
      }
    }
    shots.sort((a, b) => a.ms.compareTo(b.ms));
    final fits = start != null && inside(start);
    return MarkerDoc(
      fromMs: fromMs,
      toMs: toMs,
      startMs: fits ? start : null,
      startEdited: fits,
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

  /// The shot marked Last shot: later shots don't count.
  final int? lastShotId;
  final int nextId;

  /// The detection the untouched shots come from; undo brings it back with
  /// them.
  final ShotSensitivity sensitivity;

  /// Where the string ends: the shot marked Last shot, wherever it is.
  int? get endMs => lastShotId == null ? null : shotById(lastShotId!)?.ms;

  /// The string's shots: after START and up to the last shot.
  List<EditShot> get activeShots {
    final start = startMs;
    if (start == null) return const [];
    final end = endMs;
    return [
      for (final s in shots)
        if (s.ms > start && (end == null || s.ms <= end)) s,
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
    final end = endMs;
    return _copy(
      shots: _sorted([...shots, EditShot(id: nextId, ms: at)]),
      lastShotId: end != null && at > end ? () => nextId : null,
      nextId: nextId + 1,
    );
  }

  /// Moves a shot; the end of the string goes with the shot marked Last
  /// shot. Moving a shot to where it is changes nothing.
  MarkerDoc moveShot(int id, int ms) {
    final shot = shotById(id);
    final at = _clamp(ms);
    if (shot == null || shot.ms == at) return this;
    return _copy(
      shots: _sorted([for (final s in shots) s.id == id ? s._at(at) : s]),
    );
  }

  /// Deletes a shot. Without the shot marked Last shot, the string ends at
  /// the shot before it.
  MarkerDoc deleteShot(int id) {
    final shot = shotById(id);
    if (shot == null) return this;
    int? before;
    for (final s in shots) {
      if (s.id != id && s.ms <= shot.ms) before = s.id;
    }
    return _copy(
      shots: [
        for (final s in shots)
          if (s.id != id) s
      ],
      tombstones: [
        ...tombstones,
        if (shot.detectedMs != null) shot.detectedMs!,
      ],
      lastShotId: id == lastShotId ? () => before : null,
    );
  }

  MarkerDoc setLastShot(int id) =>
      shotById(id) == null ? this : _copy(lastShotId: () => id);

  /// Applies a new detection at [sensitivity] and keeps the user's edits:
  /// moved and added shots and the shot marked Last shot stay, untouched
  /// detected shots are replaced, and a detection near a tombstone or near
  /// a kept shot (moved shots by their detected time too) is dropped. START
  /// follows the new detection unless the user placed it or the new one
  /// found none.
  MarkerDoc reconcile({
    required int? startMs,
    required List<int> shotMs,
    ShotSensitivity? sensitivity,
  }) {
    const sameDetectionMs = 30;
    const keptShotMs = 50;
    final kept = [
      for (final s in shots)
        if (s.origin != ShotOrigin.detected || s.id == lastShotId) s
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
          EditShot(id: id++, ms: ms, detectedMs: ms),
    ];
    return _copy(
      startMs: startEdited ? this.startMs : startMs,
      shots: _sorted([...kept, ...fresh]),
      nextId: id,
      sensitivity: sensitivity,
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
    int? Function()? lastShotId,
    int? nextId,
    ShotSensitivity? sensitivity,
  }) =>
      MarkerDoc(
        fromMs: fromMs,
        toMs: toMs,
        startMs: startMs ?? this.startMs,
        startEdited: startEdited ?? this.startEdited,
        shots: shots ?? this.shots,
        tombstones: tombstones ?? this.tombstones,
        lastShotId: lastShotId == null ? this.lastShotId : lastShotId(),
        nextId: nextId ?? this.nextId,
        sensitivity: sensitivity ?? this.sensitivity,
      );
}
