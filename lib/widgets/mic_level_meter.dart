import 'package:flutter/material.dart';

/// Horizontal VU-style meter with a marker indicating the current detection
/// threshold. Both [level] and [threshold] are in the range 0..1.
///
/// [compact] drops the label row and draws a 3 dp line: the running screen's
/// only sign that the microphone is hearing anything.
class MicLevelMeter extends StatelessWidget {
  const MicLevelMeter({
    super.key,
    required this.level,
    required this.threshold,
    this.height = 14,
    this.compact = false,
  });

  final double level;
  final double threshold;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = level.clamp(0.0, 1.0);
    final thresholdClamped = threshold.clamp(0.0, 1.0);
    final overThreshold = clamped >= thresholdClamped;
    final barHeight = compact ? 3.0 : height;

    final bar = LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: barHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: compact
                    ? theme.colorScheme.outlineVariant
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(barHeight / 2),
              ),
            ),
            FractionallySizedBox(
              widthFactor: clamped,
              child: Container(
                decoration: BoxDecoration(
                  color: overThreshold
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(barHeight / 2),
                ),
              ),
            ),
            Positioned(
              left: c.maxWidth * thresholdClamped - 1,
              top: compact ? -3 : -2,
              bottom: compact ? -3 : -2,
              child: Container(
                width: 2,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );

    if (compact) {
      return Semantics(
        label: 'MIC ${(clamped * 100).round()}%',
        child: bar,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'MIC',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${(clamped * 100).round().toString().padLeft(3)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        bar,
      ],
    );
  }
}
