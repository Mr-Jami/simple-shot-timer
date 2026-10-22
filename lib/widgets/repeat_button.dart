// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/material.dart';

/// An outlined icon button that repeats while held: once on touch, then
/// after [delay] every [interval], twice as fast after [speedUpAfter].
/// [onStart] and [onEnd] bracket a hold, so its steps can be one undo.
class RepeatButton extends StatefulWidget {
  const RepeatButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onStep,
    this.onStart,
    this.onEnd,
    this.delay = const Duration(milliseconds: 400),
    this.interval = const Duration(milliseconds: 80),
    this.speedUpAfter = const Duration(seconds: 1),
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onStep;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final Duration delay;
  final Duration interval;
  final Duration speedUpAfter;

  @override
  State<RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<RepeatButton> {
  Timer? _timer;
  var _held = Duration.zero;

  void _down() {
    widget.onStart?.call();
    widget.onStep();
    _held = Duration.zero;
    _timer = Timer(widget.delay, _repeat);
  }

  void _repeat() {
    widget.onStep();
    final fast = _held >= widget.speedUpAfter;
    final next = fast ? widget.interval ~/ 2 : widget.interval;
    _held += next;
    _timer = Timer(next, _repeat);
  }

  void _up() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    widget.onEnd?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: IconButton.outlined(
        tooltip: widget.tooltip,
        icon: Icon(widget.icon),
        // The Listener does the work; the button only shows the press.
        onPressed: () {},
      ),
    );
  }
}
