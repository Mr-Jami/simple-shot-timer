// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../utils/motion.dart';

/// The app's one big action, full width: START/STOP on the Timer tab,
/// Choose video on the Video tab. Colour, icon and label change continuously
/// from wherever they are, so a rapid tap sequence never jumps; [contentKey]
/// marks when icon and label count as new content.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.background,
    this.foreground,
    this.contentKey,
  });

  static const double height = 96;

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Defaults to the scheme's primary and onPrimary.
  final Color? background;
  final Color? foreground;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onPrimary;
    final radius = BorderRadius.circular(height / 2);
    return Semantics(
      button: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: AnimatedContainer(
          duration: motion(context, kMotionMedium),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: background ?? scheme.primary,
            borderRadius: radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onPressed,
              child: Center(
                child: AnimatedSwitcher(
                  duration: motion(context, kMotionShort),
                  child: Row(
                    key: contentKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 36, color: fg),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
