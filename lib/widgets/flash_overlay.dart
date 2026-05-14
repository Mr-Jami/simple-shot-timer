import 'package:flutter/material.dart';

/// Brief full-screen white flash, driven by [trigger]. Each change in the
/// trigger value plays one flash cycle.
class FlashOverlay extends StatefulWidget {
  const FlashOverlay({
    super.key,
    required this.trigger,
    required this.child,
    this.enabled = true,
  });

  final int trigger;
  final Widget child;
  final bool enabled;

  @override
  State<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<FlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void didUpdateWidget(covariant FlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.trigger != oldWidget.trigger) {
      _ctrl.forward(from: 0).then((_) => _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => Opacity(
              opacity: _ctrl.value * 0.6,
              child: Container(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
