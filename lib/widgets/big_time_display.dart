// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../utils/motion.dart';
import '../utils/time_format.dart';

/// The headline number. Every change of [pulseKey] (the running screen
/// passes the shot count) plays a 120 ms scale tick so a detected shot is
/// visible without a list: the number itself acknowledges it.
class BigTimeDisplay extends StatefulWidget {
  const BigTimeDisplay({
    super.key,
    required this.timeMs,
    this.label,
    this.fontSize = 96,
    this.pulseKey,
  });

  final int timeMs;
  final String? label;
  final double fontSize;
  final Object? pulseKey;

  @override
  State<BigTimeDisplay> createState() => _BigTimeDisplayState();
}

class _BigTimeDisplayState extends State<BigTimeDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: kMotionTick,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 1.03)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.03, end: 1)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 1,
    ),
  ]).animate(_ctrl);

  @override
  void didUpdateWidget(covariant BigTimeDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseKey != null && widget.pulseKey != oldWidget.pulseKey) {
      _ctrl.duration = motion(context, kMotionTick);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Text(
            widget.label!,
            style: theme.textTheme.titleMedium?.copyWith(
              letterSpacing: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ScaleTransition(
          scale: _scale,
          child: Text(
            formatSeconds(widget.timeMs),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
              letterSpacing: -widget.fontSize * 0.02,
              color: theme.colorScheme.primary,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
