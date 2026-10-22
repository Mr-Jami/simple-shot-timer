// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

/// Shot number in a circle. Detected shots are filled; a shot the user added
/// by hand is outlined, which is the whole "manual" marker.
class ShotBadge extends StatelessWidget {
  const ShotBadge({super.key, required this.ordinal, required this.manual});
  final int ordinal;
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: manual ? null : scheme.surfaceContainerHighest,
        border: manual ? Border.all(color: scheme.outline) : null,
      ),
      child: Text(
        '$ordinal',
        style: TextStyle(fontSize: 12, color: scheme.onSurface),
      ),
    );
  }
}
