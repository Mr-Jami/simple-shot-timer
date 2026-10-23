// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../providers/clip_editor_provider.dart';
import '../providers/video_export_provider.dart';
import '../providers/video_providers.dart';
import '../services/video/clip_player.dart';
import '../services/video/clip_signal.dart';
import '../services/video/export_plan.dart';
import '../services/video/hud.dart';
import '../services/video/marker_doc.dart';
import '../utils/motion.dart';
import '../utils/time_format.dart';
import '../utils/timeline_math.dart';
import '../widgets/clip_video.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/editor/editor_transport.dart';
import '../widgets/editor/marker_panel.dart';
import '../widgets/editor/sensitivity_selector.dart';
import '../widgets/shot_badge.dart';
import '../widgets/string_summary_grid.dart';
import '../widgets/timeline/shot_timeline.dart';
import '../widgets/timeline/spectrogram_tiles.dart';
import '../widgets/timeline/timeline_controller.dart';
import '../widgets/timeline/timeline_minimap.dart';
import '../widgets/video/hud_overlay.dart';
import 'video_export_dialog.dart';
import 'video_export_sheet.dart';

/// The video editor: the clip pinned on top, the time readout and
/// transport, the timeline (the spectrogram scrolling under a fixed
/// playhead, shot badges and splits), the minimap and the marker panel;
/// sensitivity, stats, shots and notes below.
///
/// The markers live in [ClipEditorNotifier]; the playhead lives in a
/// [TimelineController], so playback and scrolling never rebuild the page.
/// A selected shot rides under the playhead while the timeline is dragged
/// and snaps to the nearest onset (±8 ms) when the finger lifts.
class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({super.key, required this.args});

  final ClipEditorArgs args;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _player = ClipPlayer(widget.args.session.clipPath);
  late final Ticker _playback = createTicker(_followPlayback);
  late final TimelineController _timeline = TimelineController(
    vsync: this,
    startMs: widget.args.clip.fromMs,
    endMs: widget.args.clip.toMs,
    platform: defaultTargetPlatform,
    onUserMove: _onUserMove,
    onSettle: _onSettle,
  );
  late SpectrogramTiles _tiles;
  var _tilesReady = false;
  Brightness? _tilesTheme;
  late final Float32List _levels =
      frameLevels(widget.args.clip.analysis.spectrogram);
  late final _provider = clipEditorProvider(widget.args);
  late final TextEditingController _label;
  late final TextEditingController _notes;

  final _sinceReport = Stopwatch();
  var _reportedMs = 0;
  var _dragging = false;
  var _leaving = false;

  /// The overlay preview over the video (the eye button).
  var _showHud = true;

  /// While the Export sheet is open, the exported range plays in a loop.
  (int, int)? _loop;

  /// The editor's own snack bars: "Shot deleted · Undo" goes with the
  /// editor and never shows, or acts, on the tab below.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// The markers right after the last delete, while its Undo is offered.
  MarkerDoc? _undoable;

  /// Haptic ticks at most every 50 ms while the timeline passes markers.
  final _clock = Stopwatch()..start();
  var _lastTick = Duration.zero;

  ClipEditorNotifier get _editor => ref.read(_provider.notifier);
  bool get _reduced => reducedMotionOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = ref.read(_provider);
    _label = TextEditingController(text: state.label ?? '');
    _notes = TextEditingController(text: state.notes ?? '');
    // Open just before START, so the beep and first shot are a tap away.
    final start = state.doc.startMs;
    final from = widget.args.clip.fromMs;
    _timeline.centreOn(
      start == null ? from : (start - 1500).clamp(from, start),
      animate: false,
    );
    _player.initialize().then((_) {
      if (!mounted) return;
      _player.addListener(_onPlayer);
      final at = _timeline.playheadMs.round();
      _reportedMs = at;
      unawaited(_player.settle(at));
      _playback.start();
    }, onError: (Object _) {
      // A video this phone can't play: the markers can still be checked on
      // the timeline, over a black picture.
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    // Built once per theme: quiet in the paper colour, loud in the ink.
    if (!_tilesReady || _tilesTheme != scheme.brightness) {
      if (_tilesReady) _tiles.dispose();
      _tiles = SpectrogramTiles(
        widget.args.clip.analysis.spectrogram,
        quiet: scheme.surface,
        loud: scheme.onSurface,
      );
      _tilesReady = true;
      _tilesTheme = scheme.brightness;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.dispose();
    _timeline.dispose();
    if (_tilesReady) _tiles.dispose();
    _player.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.pause();
      unawaited(_editor.flush());
    }
  }

  // Playback ------------------------------------------------------------

  void _onPlayer() {
    final ms = _player.value.position.inMilliseconds;
    if (ms != _reportedMs) {
      _reportedMs = ms;
      _sinceReport
        ..reset()
        ..start();
    }
  }

  /// While the video plays, the timeline follows it, running on between
  /// the player's position reports (every 100 ms). Playback stops at the
  /// end of the analysed part, or loops while the Export sheet is open (also
  /// when the video itself ends first).
  void _followPlayback(Duration elapsed) {
    final value = _player.value;
    final loop = _loop;
    if (!value.isPlaying) {
      if (loop != null && value.isCompleted) return _playFrom(loop.$1);
      _timeline.stopFollowing();
      return;
    }
    final clip = widget.args.clip;
    final ms =
        _reportedMs + _sinceReport.elapsedMilliseconds * value.playbackSpeed;
    if (loop != null && ms >= loop.$2) return _playFrom(loop.$1);
    if (ms >= clip.toMs) _player.pause();
    _timeline.follow(ms.round().clamp(clip.fromMs, clip.toMs));
  }

  /// Plays from [ms]: the timeline jumps there and follows from it.
  void _playFrom(int ms) {
    _timeline.centreOn(ms, animate: false);
    _reportedMs = ms;
    _sinceReport
      ..reset()
      ..start();
    _player.play();
  }

  void _togglePlay() {
    if (_player.value.isPlaying) {
      _player.pause();
    } else {
      _editor.select(null);
      final clip = widget.args.clip;
      // At the end, play the clip (or part) again from its start.
      if (_timeline.playheadMs >= clip.toMs - 100) {
        _timeline.centreOn(clip.fromMs, animate: false);
      }
      // Follow from where the video is now, not from its last report.
      _reportedMs = _timeline.playheadMs.round();
      _sinceReport
        ..reset()
        ..start();
      _player.play();
    }
  }

  /// The clip time the overlay shows: the frame on screen. While playing
  /// the picture runs about a frame behind the playhead's estimate, so the
  /// overlay goes one frame ahead; either way it snaps to frame times.
  int _hudTimeMs() {
    final frameMs = 1000 / (widget.args.clip.info.frameRate ?? 30);
    var ms = _timeline.playheadMs;
    if (_player.value.isPlaying) ms += frameMs;
    return ((ms / frameMs).floor() * frameMs).round();
  }

  /// The overlay over the video, once START is set and its size is known.
  Widget? _hud(ClipEditorState state) {
    final start = state.doc.startMs;
    final info = widget.args.clip.info;
    final frame = info.width != null && info.height != null
        ? Size(info.width!.toDouble(), info.height!.toDouble())
        : _player.value.size;
    if (!_showHud || start == null || frame.isEmpty) return null;
    return HudOverlay(
      frame: frame,
      string: HudString(_editor.draft, startMs: start),
      options: ref.watch(hudOptionsProvider),
      labels: context.hudLabels,
      timeMs: _hudTimeMs,
      repaint: _timeline,
      logo: ref.watch(hudLogoProvider).valueOrNull,
      reduceMotion: _reduced,
    );
  }

  // The user moving the timeline -----------------------------------------

  List<int> _markerTimes(MarkerDoc doc) => [
        if (doc.startMs != null) doc.startMs!,
        for (final s in doc.activeShots) s.ms,
      ]..sort();

  void _onUserMove(double fromMs, double toMs) {
    final ms = _timeline.playheadMs.round();
    _player.scrub(ms);
    final state = ref.read(_provider);
    final selected = state.selectedId;
    if (_dragging && selected != null) {
      _editor.moveShot(selected, ms);
    } else if ((_dragging || _timeline.motion == TimelineMotion.fling) &&
        crossesMarker(fromMs, toMs, _markerTimes(state.doc)) &&
        _clock.elapsed - _lastTick > const Duration(milliseconds: 50)) {
      HapticFeedback.selectionClick();
      _lastTick = _clock.elapsed;
    }
  }

  void _onSettle(int ms) {
    _reportedMs = ms;
    unawaited(_player.settle(ms));
  }

  void _onTouch() {
    _player.pause();
    _dragging = true;
    if (ref.read(_provider).selectedId != null) _editor.beginGesture();
  }

  void _onRelease() {
    _dragging = false;
    final id = ref.read(_provider).selectedId;
    if (id == null) return;
    final ms = _timeline.playheadMs.round();
    final snapped = widget.args.clip.snapToOnset(ms) ?? ms;
    _editor.moveShot(id, snapped);
    _editor.endGesture();
    if (snapped != ms) _timeline.centreOn(snapped, animate: !_reduced);
  }

  void _centre(int ms) {
    _player.pause();
    _timeline.centreOn(ms, animate: !_reduced);
  }

  void _tapMarker(TimelineMarker marker) {
    _editor.select(marker.id);
    _centre(marker.ms);
  }

  void _jump({required bool forward}) {
    final now = _timeline.playheadMs;
    final markers = _markerTimes(ref.read(_provider).doc);
    final target = forward
        ? markers.where((m) => m > now + 5).firstOrNull
        : markers.reversed.where((m) => m < now - 5).firstOrNull;
    if (target != null) _centre(target);
  }

  void _nudge(EditShot shot, int deltaMs) {
    _editor.nudge(shot.id, deltaMs);
    final moved = ref.read(_provider).doc.shotById(shot.id);
    if (moved != null) _timeline.centreOn(moved.ms, animate: false);
  }

  void _addShot() {
    HapticFeedback.lightImpact();
    _player.pause();
    _editor.addShot(_timeline.playheadMs.round());
  }

  void _delete(EditShot shot) {
    _editor.deleteShot(shot.id);
    _undoable = ref.read(_provider).doc;
    _messenger.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr('editor.deleted')),
        // One with an action stays until dismissed by default; this one
        // times out, except with a screen reader.
        persist: MediaQuery.accessibleNavigationOf(context),
        action: SnackBarAction(
          label: context.tr('editor.undo'),
          onPressed: () {
            _undoable = null;
            _editor.undo();
          },
        ),
      ));
  }

  // Export ----------------------------------------------------------------

  /// The Export sheet over the playing export, then the export itself. The
  /// string is saved first: exporting counts as keeping it.
  Future<void> _export() async {
    final start = ref.read(_provider).doc.startMs;
    if (start == null) return;
    final clip = widget.args.clip;
    final string = HudString(_editor.draft, startMs: start);
    final plan = ExportPlan(
      string,
      clip.info,
      fromMs: clip.fromMs,
      toMs: clip.toMs,
    );
    _editor.select(null);
    setState(() => _showHud = true);
    _loop = (plan.startMs, plan.endMs);
    _playFrom(plan.startMs);
    final target = await showExportSheet(context);
    _loop = null;
    await _player.pause();
    if (target == null || !mounted) return;
    await _editor.flush();
    if (!mounted) return;
    await showExportDialog(
      context,
      ExportJob(
        clip: clip,
        session: widget.args.session,
        string: string,
        plan: plan,
        options: ref.read(hudOptionsProvider),
        labels: context.hudLabels,
        logo: ref.read(hudLogoProvider).valueOrNull,
        target: target,
      ),
    );
  }

  // Leaving ---------------------------------------------------------------

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _player.pause();
    while (true) {
      await _editor.flush();
      if (!mounted) return;
      if (ref.read(_provider).saveStatus != SaveStatus.failed) break;
      final retry = await confirmDialog(
        context,
        title: context.tr('editor.saveFailedTitle'),
        body: context.tr('editor.saveFailedBody'),
        cancelLabel: context.tr('common.discard'),
        confirmLabel: context.tr('editor.retry'),
      );
      if (!retry) break;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    if (ref.read(_provider).savedId != null) {
      final sure = await confirmDialog(
        context,
        title: context.tr('editor.discardTitle'),
        body: context.tr('editor.discardBody'),
        confirmLabel: context.tr('common.discard'),
      );
      if (!sure || !mounted) return;
    }
    _leaving = true;
    await _editor.discard();
    if (mounted) Navigator.of(context).pop();
  }

  // Layout ----------------------------------------------------------------

  List<TimelineMarker> _timelineMarkers(ClipEditorState state) {
    final doc = state.doc;
    final active = {for (final s in doc.activeShots) s.id};
    var ordinal = 0;
    return [
      if (doc.startMs != null)
        TimelineMarker(ms: doc.startMs!, kind: TimelineMarkerKind.start),
      for (final s in doc.shots)
        TimelineMarker(
          ms: s.ms,
          kind: TimelineMarkerKind.shot,
          id: s.id,
          ordinal: active.contains(s.id) ? ++ordinal : null,
          manual: s.origin != ShotOrigin.detected,
          active: active.contains(s.id),
          selected: s.id == state.selectedId,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final scheme = Theme.of(context).colorScheme;
    final spectrogram = widget.args.clip.analysis.spectrogram;
    ref.listen(_provider.select((s) => s.doc), (_, doc) {
      // After any later edit, Undo would revert that, not the delete.
      if (_undoable != null && !identical(doc, _undoable)) {
        _undoable = null;
        _messenger.currentState?.hideCurrentSnackBar();
      }
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Light status bar icons over the black video; the navigation bar
        // keeps the page's colour.
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: scheme.surface,
          systemNavigationBarIconBrightness:
              scheme.brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
        ),
        child: ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            body: Column(
              children: [
                _VideoPane(
                  player: _player,
                  aspectRatio: widget.args.clip.info.aspectRatio,
                  overlay: _hud(state),
                  showOverlay: _showHud,
                  onToggleOverlay: () => setState(() => _showHud = !_showHud),
                  onBack: _leave,
                  onDiscard: _discard,
                ),
                EditorTransport(
                  player: _player,
                  timeline: _timeline,
                  startMs: state.doc.startMs,
                  onPlay: _togglePlay,
                  onPrevious: () => _jump(forward: false),
                  onNext: () => _jump(forward: true),
                ),
                ShotTimeline(
                  controller: _timeline,
                  tiles: _tiles,
                  originMs: widget.args.clip.audioOriginMs,
                  markers: _timelineMarkers(state),
                  flingEnabled: state.selectedId == null,
                  onTouch: _onTouch,
                  onRelease: _onRelease,
                  onTapMarker: _tapMarker,
                  onTapEmpty: () => _editor.select(null),
                  startLabel: context.tr('editor.start'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: TimelineMinimap(
                    controller: _timeline,
                    levels: _levels,
                    originMs: widget.args.clip.audioOriginMs,
                    frameMs: spectrogram.framesPerSecond > 0
                        ? 1000 / spectrogram.framesPerSecond
                        : 0,
                    markers: _markerTimes(state.doc),
                    onJump: _centre,
                    onScrub: (ms) {
                      _player.pause();
                      _timeline.scrubTo(ms);
                    },
                    onScrubEnd: _timeline.endScrub,
                  ),
                ),
                MarkerPanel(
                  selected: state.selected,
                  shots: state.doc.activeShots,
                  startMs: state.doc.startMs,
                  onSetStart: () =>
                      _editor.setStart(_timeline.playheadMs.round()),
                  onAddShot: _addShot,
                  onNudgeStart: _editor.beginGesture,
                  onNudge: _nudge,
                  onNudgeEnd: _editor.endGesture,
                  onDelete: _delete,
                  onLastShot: (shot) => _editor.setLastShot(shot.id),
                  onDeselect: () => _editor.select(null),
                ),
                const Divider(height: 1),
                Expanded(child: _details(context, state)),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.movie_outlined),
                      label: Text(context.tr('editor.export')),
                      onPressed: state.doc.isComplete ? _export : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Below the marker panel: sensitivity (fresh clips only), stats, the
  /// shots, then label, notes and penalty.
  Widget _details(BuildContext context, ClipEditorState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!state.reopened) ...[
          SensitivitySelector(
            value: state.sensitivity,
            busy: state.sensitivityBusy,
            onChanged: _editor.setSensitivity,
          ),
          const SizedBox(height: 16),
        ],
        StringSummaryGrid(string: _editor.draft),
        const SizedBox(height: 8),
        ..._shotRows(context, state),
        const SizedBox(height: 16),
        TextField(
          controller: _label,
          decoration: InputDecoration(
            labelText: context.tr('review.label'),
            border: const OutlineInputBorder(),
          ),
          onChanged: _editor.setLabel,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.tr('review.notes'),
            border: const OutlineInputBorder(),
          ),
          onChanged: _editor.setNotes,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(context.tr('review.penalty', args: {
                'seconds': formatSeconds(state.penaltyMs),
              })),
            ),
            IconButton(
              onPressed: () => _editor.setPenalty(state.penaltyMs - 1000),
              tooltip: context.tr('review.penaltyLess'),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              onPressed: () => _editor.setPenalty(state.penaltyMs + 1000),
              tooltip: context.tr('review.penaltyMore'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _shotRows(BuildContext context, ClipEditorState state) {
    final theme = Theme.of(context);
    final start = state.doc.startMs;
    final shots = state.doc.activeShots;
    const tabular = [FontFeature.tabularFigures()];
    return [
      if (start != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: Text(context.tr('editor.start')),
          subtitle: Text(context.tr('editor.startAt', args: {
            'seconds': formatSeconds(start, decimals: 3),
          })),
          onTap: () {
            _editor.select(null);
            _centre(start);
          },
        ),
      for (var i = 0; i < shots.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          selected: shots[i].id == state.selectedId,
          leading: ShotBadge(
            ordinal: i + 1,
            manual: shots[i].origin != ShotOrigin.detected,
          ),
          title: Text(
            '${formatSeconds(shots[i].ms - (start ?? 0), decimals: 3)}s',
            style: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabular),
          ),
          subtitle: Text(
            i == 0
                ? context.tr('review.splitFirst')
                : context.tr('review.splitOther', args: {
                    'seconds': formatSeconds(shots[i].ms - shots[i - 1].ms,
                        decimals: 3),
                  }),
            style: const TextStyle(fontFeatures: tabular),
          ),
          onTap: () {
            _editor.select(shots[i].id);
            _centre(shots[i].ms);
          },
        ),
    ];
  }
}

/// The clip on black under the status bar, a third of the screen high,
/// with the [overlay] preview on it, and back, the eye (the preview on or
/// off) and the ⋮ menu (Discard) over it.
class _VideoPane extends StatelessWidget {
  const _VideoPane({
    required this.player,
    required this.aspectRatio,
    required this.overlay,
    required this.showOverlay,
    required this.onToggleOverlay,
    required this.onBack,
    required this.onDiscard,
  });

  final ClipPlayer player;
  final double? aspectRatio;
  final Widget? overlay;
  final bool showOverlay;
  final VoidCallback onToggleOverlay;
  final VoidCallback onBack;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.3,
          child: Stack(
            children: [
              Center(
                child: ClipVideo(
                  player: player,
                  aspectRatio: aspectRatio,
                  foreground: overlay,
                ),
              ),
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
              ),
              Positioned(
                right: 52,
                top: 4,
                child: IconButton(
                  tooltip: context.tr(showOverlay
                      ? 'editor.hideOverlay'
                      : 'editor.showOverlay'),
                  color: Colors.white,
                  icon: Icon(showOverlay
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: onToggleOverlay,
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: PopupMenuButton<bool>(
                  iconColor: Colors.white,
                  onSelected: (_) => onDiscard(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: true,
                      child: Text(
                        context.tr('common.discard'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
