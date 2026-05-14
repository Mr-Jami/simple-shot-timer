import 'package:flutter/material.dart';

/// Horizontal VU-style meter with a marker indicating the current detection
/// threshold. Both [level] and [threshold] are in the range 0..1.
class MicLevelMeter extends StatelessWidget {
  const MicLevelMeter({
    super.key,
    required this.level,
    required this.threshold,
    this.height = 14,
  });

  final double level;
  final double threshold;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = level.clamp(0.0, 1.0);
    final thresholdClamped = threshold.clamp(0.0, 1.0);
    final overThreshold = clamped >= thresholdClamped;

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
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: height,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: Container(
                    decoration: BoxDecoration(
                      color: overThreshold
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
                Positioned(
                  left: c.maxWidth * thresholdClamped - 1,
                  top: -2,
                  bottom: -2,
                  child: Container(
                    width: 2,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
