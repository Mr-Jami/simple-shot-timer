// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../models/shot.dart';
import '../../models/timer_string.dart';
import '../../services/video/hud.dart';
import 'hud_overlay.dart';
import 'hud_painter.dart';

/// What a shared video looks like: a dark 16:9 frame with the overlay in
/// [options], mid-string, for the Video tab.
class HudSample extends StatelessWidget {
  const HudSample({
    super.key,
    required this.options,
    required this.labels,
    this.logo,
  });

  final HudOptions options;
  final HudLabels labels;
  final ui.Image? logo;

  static const _frame = Size(1920, 1080);

  /// Between the fifth and the sixth shot, so the clock runs and the
  /// splits show.
  static const _atMs = 4350;

  static final _string = HudString(
    TimerString(
      createdAt: DateTime(2026),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [
        for (final (i, ms)
            in const [1690, 2310, 2970, 3520, 4100, 4720].indexed)
          Shot(index: i, timeMs: ms),
      ],
    ),
    startMs: 0,
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _frame.aspectRatio,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3A3F44), Color(0xFF15181B)],
            ),
          ),
          child: HudOverlay(
            frame: _frame,
            string: _string,
            options: options,
            labels: labels,
            timeMs: () => _atMs,
            logo: logo,
          ),
        ),
      ),
    );
  }
}
