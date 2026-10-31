// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/app_localizations.dart';
import '../../utils/time_format.dart';
import '../timeline/timeline_controller.dart';

/// The video editor's time readout (from START, or in the video before
/// START is set) and its transport: previous marker, play, next marker.
class EditorTransport extends StatelessWidget {
  const EditorTransport({
    super.key,
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
                final ms = (timeline.playheadMs - (start ?? 0)).round();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${ms < 0 ? '−' : ''}'
                      '${formatSeconds(ms.abs(), decimals: 3)}s',
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
