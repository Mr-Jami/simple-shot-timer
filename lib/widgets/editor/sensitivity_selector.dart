// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../services/video/clip_analyzer.dart';

/// Fewer / Normal / More shots for a freshly analysed clip, with a spinner
/// while the analysis runs again.
class SensitivitySelector extends StatelessWidget {
  const SensitivitySelector({
    super.key,
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
