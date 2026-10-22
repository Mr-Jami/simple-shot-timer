// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../i18n/app_localizations.dart';
import '../providers/clip_editor_provider.dart';
import '../services/video/marker_doc.dart';
import '../services/video/throttled_seeker.dart';
import '../widgets/shot_badge.dart';
import '../widgets/string_summary_grid.dart';

String _clock(int ms) => (ms / 1000).toStringAsFixed(3);

/// The video editor: the clip pinned on top, a transport and scrub bar, the
/// marker panel, then the string's stats, shots and notes. Markers live in
/// [ClipEditorNotifier]; the playhead lives here, so playback and scrubbing
/// never rebuild the page.
class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({super.key, required this.args});

  final ClipEditorArgs args;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final VideoPlayerController _player = VideoPlayerController.file(
    File(widget.args.session.clipPath),
    // The texture view washes out HDR and garbles 4K 10-bit clips.
    viewType: VideoViewType.platformView,
  );
  late final ThrottledSeeker _seeker =
      ThrottledSeeker((d) => _player.seekTo(d));
  late final Ticker _ticker = createTicker(_tick);
  final _playhead = ValueNotifier<int>(0);
  final _sinceReport = Stopwatch();
  var _reportedMs = 0;
  var _scrubbing = false;
  var _leaving = false;
  late final TextEditingController _label;
  late final TextEditingController _notes;

  late final _provider = clipEditorProvider(widget.args);
  ClipEditorNotifier get _editor => ref.read(_provider.notifier);

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
      if (start != null) _seekExact(start > 1500 ? start - 1500 : 0);
      _ticker.start();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _player.dispose();
    _playhead.dispose();
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

  void _onPlayer() {
    final ms = _player.value.position.inMilliseconds;
    if (ms != _reportedMs) {
      _reportedMs = ms;
      _sinceReport
        ..reset()
        ..start();
    }
  }

  /// Between the player's position reports (every 100 ms) the playhead runs
  /// on, so the readout and markers move smoothly.
  void _tick(Duration _) {
    if (_scrubbing) return;
    final value = _player.value;
    _playhead.value = value.isPlaying
        ? (_reportedMs + _sinceReport.elapsedMilliseconds * value.playbackSpeed)
            .round()
            .clamp(0, value.duration.inMilliseconds)
        : _reportedMs;
  }

  Future<void> _seekExact(int ms) async {
    _playhead.value = ms;
    _reportedMs = ms;
    await _seeker.release(Duration(milliseconds: ms));
  }

  void _scrub(double ms) {
    _scrubbing = true;
    _player.pause();
    _playhead.value = ms.round();
    _seeker.scrub(Duration(milliseconds: ms.round()));
  }

  Future<void> _endScrub(double ms) async {
    await _seekExact(ms.round());
    _scrubbing = false;
  }

  void _togglePlay() =>
      _player.value.isPlaying ? _player.pause() : _player.play();

  List<int> _markers(MarkerDoc doc) => [
        if (doc.startMs != null) doc.startMs!,
        for (final s in doc.activeShots) s.ms,
      ]..sort();

  void _jump(MarkerDoc doc, {required bool forward}) {
    final now = _playhead.value;
    final markers = _markers(doc);
    final target = forward
        ? markers.where((m) => m > now + 5).firstOrNull
        : markers.reversed.where((m) => m < now - 5).firstOrNull;
    if (target == null) return;
    _player.pause();
    _seekExact(target);
  }

  void _addShot() {
    HapticFeedback.lightImpact();
    _editor.addShot(_playhead.value);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final info = widget.args.clip.info;
    final aspect = info.width != null && info.height != null && info.height! > 0
        ? info.width! / info.height!
        : _player.value.isInitialized
            ? _player.value.aspectRatio
            : 16 / 9;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('editor.title')),
          actions: [
            PopupMenuButton<bool>(
              onSelected: (_) => _discard(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: true,
                  child: Text(
                    context.tr('common.discard'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.38,
                ),
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: _player.value.isInitialized
                          ? VideoPlayer(_player, key: ObjectKey(_player))
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              _Transport(
                player: _player,
                playhead: _playhead,
                onPlay: _togglePlay,
                onPrevious: () => _jump(state.doc, forward: false),
                onNext: () => _jump(state.doc, forward: true),
              ),
              _ScrubBar(
                playhead: _playhead,
                durationMs: info.durationMs,
                markers: _markers(state.doc),
                onScrub: _scrub,
                onEnd: _endScrub,
              ),
              _MarkerPanel(
                state: state,
                onSetStart: () => _editor.setStart(_playhead.value),
                onAddShot: _addShot,
                onNudge: (shot, ms) => _editor.nudge(shot.id, ms),
                onDelete: _delete,
                onLastShot: (shot) => _editor.setLastShot(shot.id),
                onDeselect: () => _editor.select(null),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StringSummaryGrid(string: _editor.draft),
                    const SizedBox(height: 16),
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
    final tabular = const [FontFeature.tabularFigures()];
    return [
      if (start != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: Text(context.tr('editor.start')),
          subtitle: Text(context.tr('editor.startAt', args: {
            'seconds': _clock(start),
          })),
          onTap: () {
            _player.pause();
            _seekExact(start);
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
            '${_clock(shots[i].ms - (start ?? 0))}s',
            style: theme.textTheme.titleMedium?.copyWith(fontFeatures: tabular),
          ),
          subtitle: Text(
            i == 0
                ? context.tr('review.splitFirst')
                : context.tr('review.splitOther', args: {
                    'seconds': _clock(shots[i].ms - shots[i - 1].ms),
                  }),
            style: TextStyle(fontFeatures: tabular),
          ),
          onTap: () {
            _editor.select(shots[i].id);
            _player.pause();
            _seekExact(shots[i].ms);
          },
        ),
    ];
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.player,
    required this.playhead,
    required this.onPlay,
    required this.onPrevious,
    required this.onNext,
  });

  final VideoPlayerController player;
  final ValueNotifier<int> playhead;
  final VoidCallback onPlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: playhead,
            builder: (context, ms, _) => Text(
              '${_clock(ms)}s',
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
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

/// The scrub bar, with a tick for START and every shot.
class _ScrubBar extends StatelessWidget {
  const _ScrubBar({
    required this.playhead,
    required this.durationMs,
    required this.markers,
    required this.onScrub,
    required this.onEnd,
  });

  final ValueNotifier<int> playhead;
  final int durationMs;
  final List<int> markers;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onEnd;

  @override
  Widget build(BuildContext context) {
    final max = durationMs <= 0 ? 1.0 : durationMs.toDouble();
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Padding(
            // Slider's own track inset.
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: CustomPaint(
              painter: _TicksPainter(
                markers: markers,
                durationMs: max,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: playhead,
          builder: (context, ms, _) => Slider(
            value: ms.clamp(0, max).toDouble(),
            max: max,
            onChanged: onScrub,
            onChangeEnd: onEnd,
          ),
        ),
      ],
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({
    required this.markers,
    required this.durationMs,
    required this.color,
  });

  final List<int> markers;
  final double durationMs;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (final m in markers) {
      final x = size.width * m / durationMs;
      canvas.drawLine(
          Offset(x, size.height * 0.2), Offset(x, size.height * 0.35), paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) =>
      old.markers != markers ||
      old.durationMs != durationMs ||
      old.color != color;
}

class _MarkerPanel extends StatelessWidget {
  const _MarkerPanel({
    required this.state,
    required this.onSetStart,
    required this.onAddShot,
    required this.onNudge,
    required this.onDelete,
    required this.onLastShot,
    required this.onDeselect,
  });

  final ClipEditorState state;
  final VoidCallback onSetStart;
  final VoidCallback onAddShot;
  final void Function(EditShot shot, int ms) onNudge;
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
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
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
                      '${_clock(selected.ms - (start ?? 0))}s',
                      if (split != null)
                        context.tr('review.splitOther',
                            args: {'seconds': _clock(split)}),
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
                IconButton.outlined(
                  tooltip: context.tr('editor.nudgeEarlier'),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => onNudge(selected, -1),
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
                IconButton.outlined(
                  tooltip: context.tr('editor.nudgeLater'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => onNudge(selected, 1),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
