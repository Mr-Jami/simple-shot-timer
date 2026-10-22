// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/timer_string.dart';
import '../services/video/analyzed_clip.dart';
import '../services/video/clip_analyzer.dart';
import '../services/video/marker_doc.dart';
import '../services/video/video_work_dir.dart';
import 'history_provider.dart';
import 'settings_provider.dart';
import 'string_provider.dart';
import 'video_providers.dart';

/// What the editor opens: an analysed clip, its work folder (the editor
/// deletes it when it closes) and, when reopened from history, the saved
/// string whose markers it shows instead of the analyzer's.
class ClipEditorArgs {
  const ClipEditorArgs({
    required this.clip,
    required this.session,
    required this.importedAt,
    this.saved,
  });

  final AnalyzedClip clip;
  final VideoSession session;
  final DateTime importedAt;
  final TimerString? saved;
}

enum SaveStatus { unsaved, saving, saved, failed }

class ClipEditorState {
  const ClipEditorState({
    required this.doc,
    required this.sensitivity,
    this.selectedId,
    this.sensitivityBusy = false,
    this.label,
    this.notes,
    this.penaltyMs = 0,
    this.savedId,
    this.saveStatus = SaveStatus.unsaved,
    this.canUndo = false,
    this.reopened = false,
  });

  final MarkerDoc doc;
  final ShotSensitivity sensitivity;
  final int? selectedId;
  final bool sensitivityBusy;
  final String? label;
  final String? notes;
  final int penaltyMs;
  final int? savedId;
  final SaveStatus saveStatus;
  final bool canUndo;

  /// Opened with "Choose video again": the saved markers, no sensitivity.
  final bool reopened;

  EditShot? get selected =>
      selectedId == null ? null : doc.shotById(selectedId!);

  ClipEditorState copyWith({
    MarkerDoc? doc,
    ShotSensitivity? sensitivity,
    int? Function()? selectedId,
    bool? sensitivityBusy,
    String? Function()? label,
    String? Function()? notes,
    int? penaltyMs,
    int? savedId,
    SaveStatus? saveStatus,
    bool? canUndo,
  }) =>
      ClipEditorState(
        doc: doc ?? this.doc,
        sensitivity: sensitivity ?? this.sensitivity,
        selectedId: selectedId == null ? this.selectedId : selectedId(),
        sensitivityBusy: sensitivityBusy ?? this.sensitivityBusy,
        label: label == null ? this.label : label(),
        notes: notes == null ? this.notes : notes(),
        penaltyMs: penaltyMs ?? this.penaltyMs,
        savedId: savedId ?? this.savedId,
        saveStatus: saveStatus ?? this.saveStatus,
        canUndo: canUndo ?? this.canUndo,
        reopened: reopened,
      );
}

/// The video editor's state and rules. The markers live in an immutable
/// [MarkerDoc]; undo keeps earlier documents. Nothing is saved until the
/// user leaves with START and at least one shot; after that first save
/// every change autosaves [autosaveDelay] after the last edit. Saves run one
/// at a time, so two quick ones never insert twice.
class ClipEditorNotifier
    extends AutoDisposeFamilyNotifier<ClipEditorState, ClipEditorArgs> {
  static const autosaveDelay = Duration(milliseconds: 600);
  static const _undoLimit = 50;

  final _undo = <MarkerDoc>[];
  Timer? _autosave;
  Future<void> _saving = Future.value();
  var _sensitivityRequest = 0;
  var _discarded = false;

  @override
  ClipEditorState build(ClipEditorArgs arg) {
    ref.onDispose(() {
      _autosave?.cancel();
      unawaited(arg.session.dispose());
    });
    final saved = arg.saved;
    if (saved != null) {
      return ClipEditorState(
        doc: MarkerDoc.fromSaved(saved, durationMs: arg.clip.info.durationMs),
        sensitivity: arg.clip.analysis.sensitivity,
        label: saved.label,
        notes: saved.notes,
        penaltyMs: saved.penaltyMs,
        savedId: saved.id,
        saveStatus: SaveStatus.saved,
        reopened: true,
      );
    }
    return ClipEditorState(
      doc: arg.clip.toDoc(),
      sensitivity: arg.clip.analysis.sensitivity,
    );
  }

  /// The string as it would be saved now; the editor's stats read it.
  TimerString get draft => TimerString(
        id: state.savedId,
        createdAt: arg.importedAt,
        drillMode: DrillMode.standard,
        delayMode: DelayMode.instant,
        delayUsedMs: 0,
        pars: const [],
        shots: state.doc.toShots(),
        label: state.label,
        notes: state.notes,
        penaltyMs: state.penaltyMs,
        source: StringSource.video,
        videoStartMs: state.doc.startMs,
        videoDurationMs: arg.clip.info.durationMs,
        videoRecordedAt: arg.clip.info.creationTime,
      );

  void setStart(int ms) => _edit(state.doc.setStart(ms));

  void addShot(int ms) {
    final id = state.doc.nextId;
    _edit(state.doc.addShot(ms), selectedId: () => id);
  }

  void select(int? id) => state = state.copyWith(selectedId: () => id);

  void nudge(int id, int deltaMs) {
    final shot = state.doc.shotById(id);
    if (shot != null) _edit(state.doc.moveShot(id, shot.ms + deltaMs));
  }

  void moveShot(int id, int ms) => _edit(state.doc.moveShot(id, ms));

  void setLastShot(int id) => _edit(state.doc.setLastShot(id));

  void deleteShot(int id) => _edit(
        state.doc.deleteShot(id),
        selectedId: () => state.selectedId == id ? null : state.selectedId,
      );

  void undo() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    state = state.copyWith(
      doc: previous,
      canUndo: _undo.isNotEmpty,
      selectedId: () => previous.shotById(state.selectedId ?? -1) == null
          ? null
          : state.selectedId,
    );
    _changed();
  }

  /// Re-detects shots at [sensitivity] and keeps the user's edits. The
  /// latest request wins; reopened strings keep exactly their markers.
  Future<void> setSensitivity(ShotSensitivity sensitivity) async {
    if (state.reopened || sensitivity == state.sensitivity) return;
    final request = ++_sensitivityRequest;
    state = state.copyWith(sensitivity: sensitivity, sensitivityBusy: true);
    final ClipAnalysis analysis;
    try {
      analysis = await ref
          .read(clipAnalyzerProvider)
          .resense(arg.clip.analysis, sensitivity);
    } on Exception {
      if (request == _sensitivityRequest) {
        state = state.copyWith(sensitivityBusy: false);
      }
      return;
    }
    if (request != _sensitivityRequest) return;
    final clip = AnalyzedClip(
      info: arg.clip.info,
      analysis: analysis,
      audioOriginMs: arg.clip.audioOriginMs,
    );
    _edit(state.doc.reconcile(startMs: clip.startMs, shotMs: clip.shotMs));
    state = state.copyWith(sensitivityBusy: false);
  }

  void setLabel(String label) {
    state = state.copyWith(label: () => label.isEmpty ? null : label);
    _changed();
  }

  void setNotes(String notes) {
    state = state.copyWith(notes: () => notes.isEmpty ? null : notes);
    _changed();
  }

  void setPenalty(int penaltyMs) {
    state = state.copyWith(penaltyMs: penaltyMs < 0 ? 0 : penaltyMs);
    _changed();
  }

  /// Saves what there is to save; the editor calls it before it closes and
  /// when the app goes to the background. Completes when written.
  Future<void> flush() {
    _autosave?.cancel();
    return _enqueueSave();
  }

  /// Deletes the saved string, if any, and stops saving.
  Future<void> discard() async {
    _discarded = true;
    _autosave?.cancel();
    await _saving;
    final id = state.savedId;
    if (id != null) {
      await ref.read(videoStringStoreProvider).deleteString(id);
      _invalidate(id);
    }
  }

  void _edit(MarkerDoc doc, {int? Function()? selectedId}) {
    _undo.add(state.doc);
    if (_undo.length > _undoLimit) _undo.removeAt(0);
    state = state.copyWith(doc: doc, canUndo: true, selectedId: selectedId);
    _changed();
  }

  /// Marks the string unsaved (an edit during a write too, so the write
  /// doesn't claim it) and, once saved before, schedules the autosave.
  void _changed() {
    if (state.saveStatus != SaveStatus.unsaved) {
      state = state.copyWith(saveStatus: SaveStatus.unsaved);
    }
    if (state.savedId == null) return;
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, _enqueueSave);
  }

  Future<void> _enqueueSave() => _saving = _saving.then((_) => _persist());

  Future<void> _persist() async {
    if (_discarded) return;
    final savedId = state.savedId;
    if (savedId == null && !state.doc.isComplete) return;
    if (savedId != null && state.saveStatus == SaveStatus.saved) return;
    final store = ref.read(videoStringStoreProvider);
    state = state.copyWith(saveStatus: SaveStatus.saving);
    try {
      final draft = this.draft;
      int id;
      if (savedId == null) {
        final cap = ref.read(settingsProvider).historyCap;
        id = (await store.insertString(draft, historyCap: cap)).id!;
      } else {
        await store.updateVideoString(draft);
        id = savedId;
      }
      // An edit during the write leaves it unsaved for the next save.
      final edited = state.saveStatus != SaveStatus.saving;
      state = state.copyWith(
        savedId: id,
        saveStatus: edited ? SaveStatus.unsaved : SaveStatus.saved,
      );
      _invalidate(id);
      if (edited) {
        _autosave?.cancel();
        _autosave = Timer(autosaveDelay, _enqueueSave);
      }
    } on Exception {
      state = state.copyWith(saveStatus: SaveStatus.failed);
    }
  }

  void _invalidate(int id) {
    ref.invalidate(historyProvider);
    ref.invalidate(stringByIdProvider(id));
  }
}

final clipEditorProvider = NotifierProvider.autoDispose
    .family<ClipEditorNotifier, ClipEditorState, ClipEditorArgs>(
  ClipEditorNotifier.new,
);
