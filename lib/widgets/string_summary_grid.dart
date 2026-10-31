// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../models/timer_string.dart';
import '../utils/time_format.dart';

/// Total, first shot, fastest, slowest and average split, and the shot
/// count of a single-cycle string.
class StringSummaryGrid extends StatelessWidget {
  const StringSummaryGrid({super.key, required this.string});
  final TimerString string;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_SummaryItem>[
      _SummaryItem(
        context.tr('review.summary.total'),
        '${formatSeconds(string.totalTimeMs)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.first'),
        string.firstShotMs == null
            ? '--'
            : '${formatSeconds(string.firstShotMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.fastest'),
        string.fastestSplitMs == null
            ? '--'
            : '${formatSeconds(string.fastestSplitMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.slowest'),
        string.slowestSplitMs == null
            ? '--'
            : '${formatSeconds(string.slowestSplitMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.average'),
        string.averageSplitMs == null
            ? '--'
            : '${formatSeconds(string.averageSplitMs!)}s',
      ),
      _SummaryItem(context.tr('review.summary.shots'), '${string.shotCount}'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        for (final i in items)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Long translations (DURCHSCHNITT, ENSIMMÄINEN) shrink to
                // one line instead of wrapping out of the fixed-height tile.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    i.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  i.value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value);
  final String label;
  final String value;
}
