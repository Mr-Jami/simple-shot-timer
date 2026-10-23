// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';

/// The largest font size, at most [style]'s, at which each of [labels]
/// fits on one line [width] wide at [scaler].
double fittedLabelSize(
  Iterable<String> labels,
  TextStyle style,
  double width,
  TextScaler scaler,
) {
  const step = 0.5;
  const smallest = 6.0;
  bool fits(double size) => labels.every((label) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style.copyWith(fontSize: size)),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final ok = painter.width <= width;
        painter.dispose();
        return ok;
      });
  var size = style.fontSize ?? 12;
  while (size > smallest && !fits(size)) {
    size -= step;
  }
  return size;
}

/// The bottom tabs: Timer, Drills, Video (unless [showVideo] is off),
/// History, Settings. Five translated labels don't all fit a phone at the
/// theme's size, so they shrink together, just enough for the longest to
/// fit its tab on one line at the user's text size (which the bar caps at
/// 1.3x).
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.showVideo = true,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showVideo;

  /// Room left and right of a label inside its tab.
  static const double _labelInset = 4;

  @override
  Widget build(BuildContext context) {
    final timer = context.tr('nav.timer');
    final drills = context.tr('nav.drills');
    final video = context.tr('nav.video');
    final history = context.tr('nav.history');
    final settings = context.tr('nav.settings');
    final labels = [timer, drills, if (showVideo) video, history, settings];
    final theme = Theme.of(context);
    final barTheme = NavigationBarTheme.of(context);
    final base = barTheme.labelTextStyle;
    // Measured bold (the selected label), in the font the bar's Material
    // gives its text.
    final measured = theme.textTheme.bodyMedium!
        .merge(base?.resolve({WidgetState.selected}));
    return LayoutBuilder(builder: (context, box) {
      final tab = (box.maxWidth - MediaQuery.paddingOf(context).horizontal) /
          labels.length;
      final size = fittedLabelSize(
        labels,
        measured,
        tab - 2 * _labelInset,
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      );
      return NavigationBarTheme(
        data: barTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => base?.resolve(states)?.copyWith(fontSize: size),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.timer_outlined),
              selectedIcon: const Icon(Icons.timer),
              label: timer,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmarks_outlined),
              selectedIcon: const Icon(Icons.bookmarks),
              label: drills,
            ),
            if (showVideo)
              NavigationDestination(
                icon: const Icon(Icons.videocam_outlined),
                selectedIcon: const Icon(Icons.videocam),
                label: video,
              ),
            NavigationDestination(
              icon: const Icon(Icons.history),
              label: history,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: settings,
            ),
          ],
        ),
      );
    });
  }
}
