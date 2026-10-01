import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/enums.dart';
import '../providers/settings_provider.dart';
import '../providers/timer_provider.dart';
import '../utils/motion.dart';
import '../widgets/flash_overlay.dart';
import 'custom_drills_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Four-tab shell: Timer, Drills, History, Settings.
///
/// The bar is inert while a string is in progress (greyed, not hidden) so a
/// stray tap near STOP does nothing and nothing on screen moves. Leaving the
/// Timer tab lets a finished result collapse back to idle, the same rule as
/// pushing a detail page from it. The beep flash covers the whole shell,
/// bar included.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  void _select(int index) {
    if (index == _index) return;
    if (_index == 0) ref.read(timerProvider.notifier).resetIfFinished();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(timerProvider.select((s) => s.phase));
    final flashTick = ref.watch(timerProvider.select((s) => s.flashTick));
    final visualFlash =
        ref.watch(settingsProvider.select((s) => s.visualFlash));
    final inProgress =
        phase == TimerPhase.running || phase == TimerPhase.countdown;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // With no app bar on the Timer tab nothing else styles the system bars,
    // so pin them to the theme: the Android navigation bar continues the
    // tab bar's surface instead of sitting under it in the wrong shade.
    final iconBrightness = theme.brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    final systemBars = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: scheme.surfaceContainer,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: scheme.surfaceContainer,
    );

    return PopScope<Object?>(
      // System back on another tab returns to the timer; on the timer it
      // leaves the app as usual. A pushed page (Review, calibration) sits
      // above this route and pops first.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBars,
        child: FlashOverlay(
          trigger: flashTick,
          enabled: visualFlash,
          reducedMotion: reducedMotionOf(context),
          child: Scaffold(
            body: IndexedStack(
              index: _index,
              children: const [
                HomeScreen(),
                CustomDrillsScreen(),
                HistoryScreen(),
                SettingsScreen(),
              ],
            ),
            bottomNavigationBar: AbsorbPointer(
              absorbing: inProgress,
              child: AnimatedOpacity(
                opacity: inProgress ? 0.38 : 1,
                duration: motion(context, kMotionMedium),
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.timer_outlined),
                      selectedIcon: const Icon(Icons.timer),
                      label: context.tr('nav.timer'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.bookmarks_outlined),
                      selectedIcon: const Icon(Icons.bookmarks),
                      label: context.tr('nav.drills'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.history),
                      label: context.tr('nav.history'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      label: context.tr('nav.settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
