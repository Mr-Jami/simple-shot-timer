// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../services/video/marker_doc.dart';
import '../../utils/time_format.dart';
import '../repeat_button.dart';
import '../shot_badge.dart';

/// Under the video editor's timeline. With a shot [selected]: its number,
/// time and split, then 1 ms earlier, Delete, Last shot and 1 ms later.
/// Without: Set START and + Shot, the one to do next filled.
class MarkerPanel extends StatelessWidget {
  const MarkerPanel({
    super.key,
    required this.selected,
    required this.shots,
    required this.startMs,
    required this.onSetStart,
    required this.onAddShot,
    required this.onNudgeStart,
    required this.onNudge,
    required this.onNudgeEnd,
    required this.onDelete,
    required this.onLastShot,
    required this.onDeselect,
  });

  final EditShot? selected;

  /// The string's shots, to number the selected one and find its split.
  final List<EditShot> shots;
  final int? startMs;
  final VoidCallback onSetStart;
  final VoidCallback onAddShot;

  /// A nudge button's hold, so its steps can be one undo.
  final VoidCallback onNudgeStart;
  final void Function(EditShot shot, int deltaMs) onNudge;
  final VoidCallback onNudgeEnd;
  final ValueChanged<EditShot> onDelete;
  final ValueChanged<EditShot> onLastShot;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final shot = selected;
    return shot == null ? _markers(context) : _selected(context, shot);
  }

  Widget _selected(BuildContext context, EditShot shot) {
    final theme = Theme.of(context);
    final index = shots.indexWhere((s) => s.id == shot.id);
    final split = index > 0 ? shot.ms - shots[index - 1].ms : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              if (index >= 0)
                ShotBadge(
                  ordinal: index + 1,
                  manual: shot.origin != ShotOrigin.detected,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  [
                    '${formatSeconds(shot.ms - (startMs ?? 0), decimals: 3)}s',
                    if (split != null)
                      context.tr('review.splitOther', args: {
                        'seconds': formatSeconds(split, decimals: 3),
                      }),
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
            children: [
              RepeatButton(
                tooltip: context.tr('editor.nudgeEarlier'),
                icon: Icons.chevron_left,
                onStart: onNudgeStart,
                onStep: () => onNudge(shot, -1),
                onEnd: onNudgeEnd,
              ),
              // The two share the room between the nudges; a long label
              // (Letzter Schuss at 360 dp) shrinks rather than overflow.
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: _fitted(context.tr('common.delete')),
                  onPressed: () => onDelete(shot),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.last_page),
                  label: _fitted(context.tr('editor.lastShot')),
                  onPressed: () => onLastShot(shot),
                ),
              ),
              RepeatButton(
                tooltip: context.tr('editor.nudgeLater'),
                icon: Icons.chevron_right,
                onStart: onNudgeStart,
                onStep: () => onNudge(shot, 1),
                onEnd: onNudgeEnd,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _fitted(String label) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1),
      );

  Widget _markers(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final noStart = startMs == null;
    Widget button(bool filled, IconData icon, String label, VoidCallback on) =>
        filled
            ? FilledButton.icon(
                icon: Icon(icon), label: Text(label), onPressed: on)
            : OutlinedButton.icon(
                icon: Icon(icon), label: Text(label), onPressed: on);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          if (noStart)
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
                child: button(noStart, Icons.flag_outlined,
                    context.tr('editor.setStart'), onSetStart),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: button(!noStart, Icons.add, context.tr('editor.addShot'),
                    onAddShot),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
