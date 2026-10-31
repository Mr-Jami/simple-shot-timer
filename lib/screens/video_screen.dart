// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../providers/history_provider.dart';
import '../providers/video_providers.dart';
import '../services/video/clip_picker.dart';
import '../widgets/pill_button.dart';
import '../widgets/string_tile.dart';
import '../widgets/tab_header.dart';
import '../widgets/video/hud_overlay.dart';
import '../widgets/video/hud_sample.dart';
import 'review_screen.dart';
import 'video_flows.dart';

/// The Video tab: choose a range video (Photos, or Files) and let the app
/// find the beep and the shots; recent video strings below.
class VideoScreen extends ConsumerWidget {
  const VideoScreen({super.key});

  static const _recentCount = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(historyProvider.select((h) => [
          for (final s in h.valueOrNull ?? const [])
            if (s.isVideo) s,
        ].take(_recentCount).toList()));
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(title: context.tr('video.title')),
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _Sample(),
                ),
                if (recent.isEmpty)
                  const _EmptyState()
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      context.tr('video.recent'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final (i, s) in recent.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    StringTile(
                      string: s,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReviewScreen(stringId: s.id!),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                PillButton(
                  icon: Icons.video_library_outlined,
                  label: context.tr('video.choose'),
                  onPressed: () => startVideoImport(context, ClipSource.photos),
                ),
                TextButton(
                  onPressed: () => startVideoImport(context, ClipSource.files),
                  child: Text(context.tr('video.chooseFiles')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a shared video looks like, in the overlay style last chosen.
class _Sample extends ConsumerWidget {
  const _Sample();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HudSample(
      options: ref.watch(hudOptionsProvider),
      labels: context.hudLabels,
      logo: ref.watch(hudLogoProvider).valueOrNull,
    );
  }
}

/// Before the first video string: what the tab does, and that the video
/// stays on the phone.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
      child: Column(
        children: [
          Text(
            context.tr('video.empty'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('video.privacy'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
