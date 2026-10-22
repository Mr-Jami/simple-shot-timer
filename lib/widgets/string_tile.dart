// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../i18n/app_localizations.dart';
import '../models/enums.dart';
import '../models/timer_string.dart';
import '../utils/time_format.dart';

/// One-line drill summary for a string's row, e.g. "Par 2.0s ×4 / 5s rest",
/// "Stage 60s", "Standard", "Video". Keeps the user from having to open
/// every entry to know which drill produced it.
String drillSummary(BuildContext context, TimerString s) {
  if (s.isVideo) return context.tr('history.video');
  String fmt(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
  switch (s.drillMode) {
    case DrillMode.standard:
      return s.drillMode.labelFor(context);
    case DrillMode.stage:
      final stageMs = s.pars.isNotEmpty ? s.pars.first.durationMs : null;
      if (stageMs == null) return s.drillMode.labelFor(context);
      return '${s.drillMode.labelFor(context)} ${fmt(stageMs)}';
    case DrillMode.par:
      final parMs = s.pars.isNotEmpty ? s.pars.first.durationMs : null;
      final repeats = s.parRepeatCount ?? 1;
      final intervalMs = s.parIntervalMs ?? 0;
      final parts = <String>[s.drillMode.labelFor(context)];
      if (parMs != null) parts.add(fmt(parMs));
      if (repeats > 1) parts.add('×$repeats');
      if (repeats > 1 && intervalMs > 0) parts.add('/${fmt(intervalMs)}');
      return parts.join(' ');
  }
}

/// A saved string in a list (History, the Video tab): its label or total and
/// shot count, the date and drill, and the total time.
class StringTile extends StatelessWidget {
  const StringTile({super.key, required this.string, this.onTap});

  final TimerString string;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = string;
    final dateFmt = DateFormat.yMMMd(context.dateLocale).add_jm();
    final summary = drillSummary(context, s);
    return ListTile(
      title: Text(
        s.label?.isNotEmpty == true
            ? s.label!
            : s.shotCount == 1
                ? context.tr('history.itemFallbackOne', args: {
                    'seconds': formatSeconds(s.totalTimeMs),
                  })
                : context.tr('history.itemFallback', args: {
                    'seconds': formatSeconds(s.totalTimeMs),
                    'count': s.shotCount,
                  }),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${dateFmt.format(s.createdAt.toLocal())} · '),
          if (s.isVideo) ...[
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.videocam_outlined, size: 16),
            ),
            const TextSpan(text: ' '),
          ],
          TextSpan(text: summary),
        ]),
      ),
      trailing: Text(
        '${formatSeconds(s.totalTimeMs)}s',
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
