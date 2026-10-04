// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

/// Visual beep. Each *increase* of [trigger] plays one signal over [child].
///
/// Default signal: a single full-screen pulse, 120 ms to peak and 180 ms
/// back, peaking at 45% white in light themes and 35% in dark ones. Bright
/// enough to catch in peripheral vision through shooting glasses, short
/// enough not to read as a strobe six times per par string.
///
/// With [reducedMotion] the pulse is replaced by a thick ring at the screen
/// edge that fades in and out over 250 ms: the signal stays, the brightness
/// jump goes.
///
/// Only a higher trigger counts. A new run resets the counter to zero and
/// that reset must never look like a beep.
class FlashOverlay extends StatefulWidget {
  const FlashOverlay({
    super.key,
    required this.trigger,
    required this.child,
    this.enabled = true,
    this.reducedMotion = false,
  });

  final int trigger;
  final Widget child;
  final bool enabled;
  final bool reducedMotion;

  @override
  State<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<FlashOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _pulseDuration = Duration(milliseconds: 300);
  static const Duration _ringDuration = Duration(milliseconds: 250);
  static const double _ringWidth = 12;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _pulseDuration,
  );

  late final Animation<double> _pulse = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 0, end: 1)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 120,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 0)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 180,
    ),
  ]).animate(_ctrl);

  late final Animation<double> _ring = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 50),
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 100),
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 100),
  ]).animate(_ctrl);

  @override
  void didUpdateWidget(covariant FlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.trigger > oldWidget.trigger) {
      _ctrl.duration = widget.reducedMotion ? _ringDuration : _pulseDuration;
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
    final peak = theme.brightness == Brightness.dark ? 0.35 : 0.45;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                if (!_ctrl.isAnimating) return const SizedBox.shrink();
                if (widget.reducedMotion) {
                  return Opacity(
                    opacity: _ring.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.onSurface,
                          width: _ringWidth,
                        ),
                      ),
                    ),
                  );
                }
                return Opacity(
                  opacity: _pulse.value * peak,
                  child: const ColoredBox(color: Colors.white),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
