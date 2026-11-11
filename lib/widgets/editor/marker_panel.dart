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
/// time, split and Done, then 1 ms earlier, Delete, Last shot and 1 ms
/// later, then a line saying that dragging the timeline moves the shot.
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
    required this.onDone,
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

  /// Done: the selected shot stays where it is and is no longer selected,
  /// so the timeline scrolls again instead of moving it.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final shot = selected;
    return shot == null ? _markers(context) : _selected(context, shot);
  }

  Widget _selected(BuildContext context, EditShot shot) {
    final theme = Theme.of(context);
    final index = shots.indexWhere((s) => s.id == shot.id);
    final split = index > 0 ? shot.ms - shots[index - 1].ms : null;
    const tabular = [FontFeature.tabularFigures()];
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
              // The split under the time, as in the list of shots: side by
              // side they wrap next to Done on a narrow screen.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatSeconds(shot.ms - (startMs ?? 0), decimals: 3)}s',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontFeatures: tabular),
                    ),
                    if (split != null)
                      Text(
                        context.tr('review.splitOther', args: {
                          'seconds': formatSeconds(split, decimals: 3),
                        }),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: tabular,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(context.tr('editor.done')),
                onPressed: onDone,
              ),
              const SizedBox(width: 8),
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
          // Right under the buttons: they have air below their icons.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _hint(context, Icons.swipe_outlined, 'editor.dragHint'),
          ),
        ],
      ),
    );
  }

  /// A small grey line of help with its icon.
  static Widget _hint(BuildContext context, IconData icon, String key) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.tr(key),
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  static Widget _fitted(String label) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1),
      );

  Widget _markers(BuildContext context) {
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
              child: _hint(context, Icons.info_outline, 'editor.noStart'),
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
