// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/enums.dart';
import '../providers/settings_provider.dart';
import '../providers/video_export_provider.dart';

/// The Export sheet: the overlay's style and corner and the end card, then
/// Save to Photos or Share. It leaves the editor's video in view, where the
/// export plays with the overlay as chosen; the choices are kept.
Future<ExportTarget?> showExportSheet(BuildContext context) =>
    showModalBottomSheet<ExportTarget>(
      context: context,
      showDragHandle: true,
      // As tall as its content: the default 9/16 cap cut off Share.
      isScrollControlled: true,
      // Light, so the preview above stays clear.
      barrierColor: Colors.black12,
      builder: (_) => const _ExportSheet(),
    );

class _ExportSheet extends ConsumerWidget {
  const _ExportSheet();

  static const _corners = {
    HudCorner.topLeft: Icons.north_west,
    HudCorner.topRight: Icons.north_east,
    HudCorner.bottomLeft: Icons.south_west,
    HudCorner.bottomRight: Icons.south_east,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final update = ref.read(settingsProvider.notifier).update;
    Widget label(String key) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(context.tr(key), style: theme.textTheme.titleSmall),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('export.title'), style: theme.textTheme.titleLarge),
            label('export.style'),
            SegmentedButton<HudStyle>(
              showSelectedIcon: false,
              segments: [
                for (final s in HudStyle.values)
                  ButtonSegment(
                    value: s,
                    label: Text(
                      context.tr('export.style.${s.name}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {settings.hudStyle},
              onSelectionChanged: (s) =>
                  update((a) => a.copyWith(hudStyle: s.single)),
            ),
            label('export.corner'),
            SegmentedButton<HudCorner>(
              showSelectedIcon: false,
              segments: [
                for (final MapEntry(key: corner, value: icon)
                    in _corners.entries)
                  ButtonSegment(
                    value: corner,
                    icon: Icon(icon),
                    tooltip: context.tr('export.corner.${corner.name}'),
                  ),
              ],
              selected: {settings.hudCorner},
              onSelectionChanged: (s) =>
                  update((a) => a.copyWith(hudCorner: s.single)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('export.endCard')),
              value: settings.hudEndCard,
              onChanged: (v) => update((a) => a.copyWith(hudEndCard: v)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.download_outlined),
              label: Text(context.tr('export.save')),
              onPressed: () => Navigator.pop(context, ExportTarget.photos),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.share_outlined),
              label: Text(context.tr('export.share')),
              onPressed: () => Navigator.pop(context, ExportTarget.share),
            ),
          ],
        ),
      ),
    );
  }
}
