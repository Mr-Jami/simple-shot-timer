// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../providers/video_import_provider.dart';
import '../services/video/clip_player.dart';
import '../services/video/part_window.dart';
import '../utils/motion.dart';
import '../utils/time_format.dart';
import '../widgets/clip_video.dart';
import '../widgets/part_strip.dart';

/// Choose the part, for clips over three minutes: a preview that shows the
/// frame under the edge being dragged and plays the window, the
/// [PartStrip], and "Analyze this part".
class VideoPartView extends StatefulWidget {
  const VideoPartView({
    super.key,
    required this.part,
    required this.onChanged,
    required this.onAnalyse,
    required this.onClose,
  });

  final ImportChoosePart part;
  final ValueChanged<PartWindow> onChanged;
  final VoidCallback onAnalyse;
  final VoidCallback onClose;

  @override
  State<VideoPartView> createState() => _VideoPartViewState();
}

class _VideoPartViewState extends State<VideoPartView> {
  late final _player = ClipPlayer(widget.part.clipPath);
  var _dragging = false;
  var _previewMs = 0;

  PartWindow get _window => widget.part.window;

  @override
  void initState() {
    super.initState();
    _player.initialize().then((_) {
      if (!mounted) return;
      _player.addListener(_onPlayer);
      unawaited(_player.settle(_window.startMs));
    }, onError: (Object _) {
      // A video this phone can't play: the part can still be chosen by its
      // filmstrip and loudness, over a black preview.
    });
  }

  @override
  void didUpdateWidget(VideoPartView old) {
    super.didUpdateWidget(old);
    // The scan placed the window: show where it starts now.
    if (!_dragging &&
        old.part.window != _window &&
        _player.value.isInitialized) {
      _player.pause();
      unawaited(_player.settle(_window.startMs));
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Playback stays inside the window.
  void _onPlayer() {
    final value = _player.value;
    if (value.isPlaying && value.position.inMilliseconds >= _window.endMs) {
      _player.pause();
    }
  }

  Future<void> _togglePlay() async {
    final value = _player.value;
    if (value.isPlaying) {
      _player.pause();
      return;
    }
    final at = value.position.inMilliseconds;
    // The seek lands first: at the end of the video, play() would start
    // over at 0 instead.
    if (at < _window.startMs || at >= _window.endMs - 100) {
      await _player.settle(_window.startMs);
      if (!mounted) return;
    }
    await _player.play();
  }

  void _changed(PartWindow window, PartEdge edge) {
    _dragging = true;
    _player.pause();
    _previewMs = edge == PartEdge.end ? window.endMs : window.startMs;
    _player.scrub(_previewMs);
    widget.onChanged(window);
  }

  void _changeEnd() {
    _dragging = false;
    unawaited(_player.settle(_previewMs));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final part = widget.part;
    final info = part.info;
    final window = _window;
    final figures = theme.textTheme.titleMedium
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(
            children: [
              CloseButton(onPressed: widget.onClose),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  context.tr('part.title'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipVideo(
                        player: _player,
                        aspectRatio: info.aspectRatio ?? 16 / 9,
                      ),
                      ValueListenableBuilder(
                        valueListenable: _player,
                        builder: (context, value, _) => IconButton.filled(
                          tooltip: context.tr(
                              value.isPlaying ? 'editor.pause' : 'editor.play'),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.5),
                            foregroundColor: Colors.white,
                          ),
                          iconSize: 32,
                          onPressed: value.isInitialized ? _togglePlay : null,
                          icon: Icon(
                              value.isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr(part.scanned ? 'part.hint' : 'part.scanning'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${formatMinutes(window.startMs)} – ${formatMinutes(window.endMs)}',
                    style: figures,
                  ),
                  const Spacer(),
                  Text(
                    formatMinutes(window.lengthMs),
                    style: figures?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PartStrip(
                durationMs: info.durationMs,
                window: window,
                loudness: part.loudness,
                bucketMs: VideoImportController.loudnessBucketMs,
                thumbnails: part.thumbnails,
                onChanged: _changed,
                onChangeEnd: _changeEnd,
                reduceMotion: reducedMotionOf(context),
                semanticLabel: context.tr('part.semantics', args: {
                  'from': formatMinutes(window.startMs),
                  'to': formatMinutes(window.endMs),
                }),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.graphic_eq),
                label: Text(context.tr('part.analyze')),
                onPressed: widget.onAnalyse,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
