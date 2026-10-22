// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../i18n/app_localizations.dart';
import '../providers/clip_editor_provider.dart';
import '../services/video/clip_analyzer.dart';
import '../services/video/clip_signal.dart';
import '../services/video/marker_doc.dart';
import '../services/video/throttled_seeker.dart';
import '../utils/motion.dart';
import '../utils/timeline_math.dart';
import '../widgets/repeat_button.dart';
import '../widgets/shot_badge.dart';
import '../widgets/string_summary_grid.dart';
import '../widgets/timeline/shot_timeline.dart';
import '../widgets/timeline/spectrogram_tiles.dart';
import '../widgets/timeline/timeline_controller.dart';
import '../widgets/timeline/timeline_minimap.dart';

String _seconds(num ms) => (ms / 1000).toStringAsFixed(3);

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
  late final VideoPlayerController _player = VideoPlayerController.file(
    File(widget.args.session.clipPath),
    // The texture view washes out HDR and garbles 4K 10-bit clips.
    viewType: VideoViewType.platformView,
  );
  late final ThrottledSeeker _seeker =
      ThrottledSeeker((d) => _player.seekTo(d));
  late final Ticker _playback = createTicker(_followPlayback);
  late final TimelineController _timeline = TimelineController(
    vsync: this,
    durationMs: widget.args.clip.info.durationMs,
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
    _player.initialize().then((_) {
      if (!mounted) return;
      _player.addListener(_onPlayer);
      // Open just before START, so the beep and first shot are a tap away.
      final start = ref.read(_provider).doc.startMs;
      final at = start == null ? 0 : (start - 1500).clamp(0, start);
      _timeline.centreOn(at, animate: false);
      _playback.start();
      setState(() {});
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
  /// the player's position reports (every 100 ms).
  void _followPlayback(Duration elapsed) {
    final value = _player.value;
    if (!value.isPlaying) {
      _timeline.stopFollowing();
      return;
    }
    final ms =
        _reportedMs + _sinceReport.elapsedMilliseconds * value.playbackSpeed;
    _timeline.follow(ms.round().clamp(0, value.duration.inMilliseconds));
  }

  void _togglePlay() {
    if (_player.value.isPlaying) {
      _player.pause();
    } else {
      _editor.select(null);
      _player.play();
    }
  }

  // The user moving the timeline -----------------------------------------

  List<int> _markerTimes(MarkerDoc doc) => [
        if (doc.startMs != null) doc.startMs!,
        for (final s in doc.activeShots) s.ms,
      ]..sort();

  void _onUserMove(double fromMs, double toMs) {
    final ms = _timeline.playheadMs.round();
    _seeker.scrub(Duration(milliseconds: ms));
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
    unawaited(_seeker.release(Duration(milliseconds: ms)));
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr('editor.deleted')),
        action: SnackBarAction(
          label: context.tr('editor.undo'),
          onPressed: _editor.undo,
        ),
      ));
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
      final retry = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('editor.saveFailedTitle')),
          content: Text(context.tr('editor.saveFailedBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('common.discard')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('editor.retry')),
            ),
          ],
        ),
      );
      if (retry != true) break;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    if (ref.read(_provider).savedId != null) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('editor.discardTitle')),
          content: Text(context.tr('editor.discardBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('common.discard')),
            ),
          ],
        ),
      );
      if (sure != true) return;
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
    final info = widget.args.clip.info;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aspect = info.width != null && info.height != null && info.height! > 0
        ? info.width! / info.height!
        : _player.value.isInitialized
            ? _player.value.aspectRatio
            : 16 / 9;
    final spectrogram = widget.args.clip.analysis.spectrogram;
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
        child: Scaffold(
          body: Column(
            children: [
              ColoredBox(
                color: Colors.black,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.3,
                    child: Stack(
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: aspect,
                            child: _player.value.isInitialized
                                ? VideoPlayer(_player, key: ObjectKey(_player))
                                : const SizedBox.expand(),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          top: 4,
                          child: IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _leave,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: PopupMenuButton<bool>(
                            iconColor: Colors.white,
                            onSelected: (_) => _discard(),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: true,
                                child: Text(
                                  context.tr('common.discard'),
                                  style: TextStyle(color: scheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _Transport(
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
                ),
              ),
              _MarkerPanel(
                state: state,
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!state.reopened) ...[
                      _SensitivitySelector(
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
                            'seconds':
                                (state.penaltyMs / 1000).toStringAsFixed(2),
                          })),
                        ),
                        IconButton(
                          onPressed: () =>
                              _editor.setPenalty(state.penaltyMs - 1000),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          onPressed: () =>
                              _editor.setPenalty(state.penaltyMs + 1000),
                          icon: const Icon(Icons.add),
                        ),
                      ],
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
            'seconds': _seconds(start),
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
            '${_seconds(shots[i].ms - (start ?? 0))}s',
            style: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabular),
          ),
          subtitle: Text(
            i == 0
                ? context.tr('review.splitFirst')
                : context.tr('review.splitOther', args: {
                    'seconds': _seconds(shots[i].ms - shots[i - 1].ms),
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

/// Time from START (or in the video, before START is set), and the
/// transport buttons.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.player,
    required this.timeline,
    required this.startMs,
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
  });

  final VideoPlayerController player;
  final TimelineController timeline;
  final int? startMs;
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = startMs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: timeline,
              builder: (context, _) {
                final ms = timeline.playheadMs - (start ?? 0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${ms < 0 ? '−' : ''}${_seconds(ms.abs())}s',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      context.tr(start == null
                          ? 'editor.inVideo'
                          : 'editor.fromStart'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: context.tr('editor.previous'),
            icon: const Icon(Icons.skip_previous_outlined),
            onPressed: onPrevious,
          ),
          ValueListenableBuilder(
            valueListenable: player,
            builder: (context, value, _) => IconButton.filled(
              tooltip:
                  context.tr(value.isPlaying ? 'editor.pause' : 'editor.play'),
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: value.isInitialized ? onPlay : null,
            ),
          ),
          IconButton(
            tooltip: context.tr('editor.next'),
            icon: const Icon(Icons.skip_next_outlined),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _SensitivitySelector extends StatelessWidget {
  const _SensitivitySelector({
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final ShotSensitivity value;
  final bool busy;
  final ValueChanged<ShotSensitivity> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(context.tr('settings.sensitivity'),
                style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              height: 14,
              child:
                  busy ? const CircularProgressIndicator(strokeWidth: 2) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<ShotSensitivity>(
          showSelectedIcon: false,
          segments: [
            for (final s in ShotSensitivity.values)
              ButtonSegment(
                value: s,
                label: Text(
                  context.tr('editor.sens.${s.name}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.single),
        ),
      ],
    );
  }
}

class _MarkerPanel extends StatelessWidget {
  const _MarkerPanel({
    required this.state,
    required this.onSetStart,
    required this.onAddShot,
    required this.onNudgeStart,
    required this.onNudge,
    required this.onNudgeEnd,
    required this.onDelete,
    required this.onLastShot,
    required this.onDeselect,
  });

  final ClipEditorState state;
  final VoidCallback onSetStart;
  final VoidCallback onAddShot;
  final VoidCallback onNudgeStart;
  final void Function(EditShot shot, int ms) onNudge;
  final VoidCallback onNudgeEnd;
  final ValueChanged<EditShot> onDelete;
  final ValueChanged<EditShot> onLastShot;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = state.selected;
    final shots = state.doc.activeShots;
    final start = state.doc.startMs;
    if (selected != null) {
      final index = shots.indexWhere((s) => s.id == selected.id);
      final split = index > 0 ? selected.ms - shots[index - 1].ms : null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                if (index >= 0)
                  ShotBadge(
                    ordinal: index + 1,
                    manual: selected.origin != ShotOrigin.detected,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      '${_seconds(selected.ms - (start ?? 0))}s',
                      if (split != null)
                        context.tr('review.splitOther',
                            args: {'seconds': _seconds(split)}),
                    ].join(' · '),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  onPressed: onDeselect,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RepeatButton(
                  tooltip: context.tr('editor.nudgeEarlier'),
                  icon: Icons.chevron_left,
                  onStart: onNudgeStart,
                  onStep: () => onNudge(selected, -1),
                  onEnd: onNudgeEnd,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.tr('common.delete')),
                  onPressed: () => onDelete(selected),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.last_page),
                  label: Text(context.tr('editor.lastShot')),
                  onPressed: () => onLastShot(selected),
                ),
                RepeatButton(
                  tooltip: context.tr('editor.nudgeLater'),
                  icon: Icons.chevron_right,
                  onStart: onNudgeStart,
                  onStep: () => onNudge(selected, 1),
                  onEnd: onNudgeEnd,
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          if (start == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('editor.noStart'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: start == null
                    ? FilledButton.icon(
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(context.tr('editor.setStart')),
                        onPressed: onSetStart,
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Icons.flag_outlined),
                        label: Text(context.tr('editor.setStart')),
                        onPressed: onSetStart,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: start == null
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('editor.addShot')),
                        onPressed: onAddShot,
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('editor.addShot')),
                        onPressed: onAddShot,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
