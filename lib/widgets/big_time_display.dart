import 'package:flutter/material.dart';

import '../utils/time_format.dart';

class BigTimeDisplay extends StatelessWidget {
  const BigTimeDisplay({
    super.key,
    required this.timeMs,
    this.label,
    this.fontSize = 96,
  });

  final int timeMs;
  final String? label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(
            label!,
            style: theme.textTheme.titleMedium?.copyWith(
              letterSpacing: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Text(
          formatSeconds(timeMs),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
