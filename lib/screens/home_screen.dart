import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/drill_config.dart';
import '../models/enums.dart';
import '../models/timer_state.dart';
import '../models/timer_string.dart';
import '../providers/custom_drills_provider.dart';
import '../providers/history_provider.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../providers/timer_provider.dart';
import '../utils/motion.dart';
import '../utils/time_format.dart';
import '../widgets/big_time_display.dart';
import '../widgets/mic_level_meter.dart';
import 'review_screen.dart';

/// Pushes [screen] from the timer and, on return, lets a finished result
/// collapse back to idle. Leaving the timer is the natural end of a result;
/// coming back to a stale "TOTAL" would read as current.
typedef OpenScreen = Future<void> Function(Widget screen);

/// The Timer tab: no header, the whole height for the string and the one
/// button. Hosted by `MainShell`, which owns the bottom bar and the flash.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerProvider);

    ref.listen(timerProvider, (prev, next) async {
      if (next.error != null && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr(next.error!))),
        );
      }
    });

    Future<void> open(Widget screen) async {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
      ref.read(timerProvider.notifier).resetIfFinished();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(child: _TimerArea(state: state, onOpen: open)),
            const SizedBox(height: 16),
            _BigButton(state: state),
          ],
        ),
      ),
    );
  }
}

/// The one control. Full width in every state; only its colour, icon and
/// label change, and they change continuously from wherever they are, so a
/// rapid START–STOP–START never jumps.
class _BigButton extends ConsumerWidget {
  const _BigButton({required this.state});
  final TimerState state;

  static const double _height = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final inProgress = state.phase == TimerPhase.running ||
        state.phase == TimerPhase.countdown;
    final background = inProgress ? Colors.red : scheme.primary;
    final foreground = inProgress ? Colors.white : scheme.onPrimary;
    final label =
        inProgress ? context.tr('home.stop') : context.tr('home.start');
    final radius = BorderRadius.circular(_height / 2);
    return Semantics(
      button: true,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: AnimatedContainer(
          duration: motion(context, kMotionMedium),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(color: background, borderRadius: radius),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: inProgress ? notifier.stop : notifier.start,
              child: Center(
                child: AnimatedSwitcher(
                  duration: motion(context, kMotionShort),
                  child: Row(
                    key: ValueKey(inProgress),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        inProgress ? Icons.stop : Icons.play_arrow,
                        size: 36,
                        color: foreground,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: foreground,
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

class _TimerArea extends ConsumerWidget {
  const _TimerArea({required this.state, required this.onOpen});
  final TimerState state;
  final OpenScreen onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final activeDrillName =
        ref.watch(activeDrillProvider.select((d) => d?.name));
    final Widget view = switch (state.phase) {
      TimerPhase.idle => _IdleView(
          settings: settings,
          activeDrillName: activeDrillName,
          onOpen: onOpen,
        ),
      TimerPhase.countdown => _CountdownView(
          state: state,
          settings: settings,
          activeDrillName: activeDrillName,
        ),
      TimerPhase.running => _RunningView(state: state, settings: settings),
      TimerPhase.finished => _FinishedView(state: state, onOpen: onOpen),
    };
    return AnimatedSwitcher(
      duration: motion(context, kMotionMedium),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(state.phase), child: view),
    );
  }
}

/// Reserves the same height above the centrepiece in the countdown and
/// running views, so STAND BY and the big number sit on one anchor.
class _TopSlot extends StatelessWidget {
  const _TopSlot({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 104),
        child: Align(alignment: Alignment.topCenter, child: child),
      );
}

/// The block under the centrepiece: optional notice, stat row, and the mic
/// line. The countdown renders it invisible so the layout does not move
/// when the string starts.
class _RunFooter extends StatelessWidget {
  const _RunFooter({
    required this.stats,
    required this.line,
    this.notice,
    this.visible = true,
  });

  final Widget stats;
  final Widget line;
  final Widget? notice;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        stats,
        const SizedBox(height: 12),
        line,
      ],
    );
    return Column(
      children: [
        if (notice != null) ...[notice!, const SizedBox(height: 8)],
        Visibility(
          visible: visible,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: body,
        ),
      ],
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({
    required this.settings,
    required this.activeDrillName,
    required this.onOpen,
  });
  final AppSettings settings;
  final String? activeDrillName;
  final OpenScreen onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(historyProvider).value;
    final last = history == null || history.isEmpty ? null : history.first;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, size: 96, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            context.tr('home.ready'),
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('home.pressStartToBegin'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _SettingsSummary(
            settings: settings,
            activeDrillName: activeDrillName,
          ),
          if (last != null) ...[
            const SizedBox(height: 16),
            _LastStringLine(
              string: last,
              onTap: () => onOpen(ReviewScreen(stringId: last.id!)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line on the idle screen keeping the newest result within reach.
class _LastStringLine extends StatelessWidget {
  const _LastStringLine({required this.string, required this.onTap});
  final TimerString string;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              string.shotCount == 1
                  ? context.tr('home.lastStringOne', args: {
                      'seconds': formatSeconds(string.totalTimeMs),
                    })
                  : context.tr('home.lastString', args: {
                      'seconds': formatSeconds(string.totalTimeMs),
                      'count': string.shotCount,
                    }),
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({
    required this.state,
    required this.settings,
    required this.activeDrillName,
  });
  final TimerState state;
  final AppSettings settings;
  final String? activeDrillName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _TopSlot(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _SettingsSummary(
              settings: settings,
              activeDrillName: activeDrillName,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hourglass_top,
                  size: 96,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('home.standBy'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        _RunFooter(
          visible: false,
          notice: state.beepInaudible ? const _InaudibleNotice() : null,
          stats: const _StatsRow(shotCount: 0, firstShotMs: null, splitMs: null),
          line: const SizedBox(height: 3),
        ),
      ],
    );
  }
}

/// The drill's configuration as read-only chips, led by the name of the
/// saved custom drill the current settings match, if any.
class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.settings, this.activeDrillName});
  final AppSettings settings;
  final String? activeDrillName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = DrillConfig.fromSettings(settings).chipLabels(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (activeDrillName != null) _ActiveDrillChip(name: activeDrillName!),
        for (final c in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              c,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Emphasised pill naming the loaded custom drill (issue #24), so the user
/// sees at a glance which saved drill the chips next to it describe.
class _ActiveDrillChip extends StatelessWidget {
  const _ActiveDrillChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark, size: 14, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.state, required this.settings});
  final TimerState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Show per-cycle data so the time + stats restart from zero at each par
    // beep — the user wants to see "this cycle's results", not a running
    // tally across cycles.
    final last = state.currentCycleLastShot;
    final displayMs = last?.timeMs ?? state.elapsedMs;
    final showCycleBanner = settings.drillMode == DrillMode.par &&
        settings.parRepeatCount > 1;
    return Column(
      children: [
        _TopSlot(
          child: showCycleBanner
              ? Text(
                  context.tr('home.cycleOf', args: {
                    'current': state.currentParIndex,
                    'total': settings.parRepeatCount,
                  }),
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Center(
            child: BigTimeDisplay(
              timeMs: displayMs,
              label: last == null
                  ? context.tr('home.time')
                  : context.tr('home.last'),
              pulseKey: state.shotCount,
            ),
          ),
        ),
        _RunFooter(
          notice: state.beepInaudible ? const _InaudibleNotice() : null,
          stats: _StatsRow(
            shotCount: state.currentCycleShotCount,
            firstShotMs: state.currentCycleFirstShotMs,
            splitMs: state.currentCycleLastSplitMs,
          ),
          line: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: MicLevelMeter(
              level: state.micLevel,
              threshold: settings.detectionThreshold,
              compact: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// One line, only while it is true: the beep cannot be heard. Tapping opens
/// the system volume control where the platform has one.
class _InaudibleNotice extends ConsumerWidget {
  const _InaudibleNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => ref.read(volumeServiceProvider).showVolumePanel(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.volume_off, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.tr('home.beepInaudible'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends ConsumerWidget {
  const _FinishedView({required this.state, required this.onOpen});
  final TimerState state;
  final OpenScreen onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(timerProvider.notifier);
    final addShot = OutlinedButton.icon(
      icon: const Icon(Icons.add),
      label: Text(context.tr('home.addShot')),
      onPressed: notifier.addManualShot,
    );

    if (state.nothingRecorded) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.tr('home.noShotsDetected'),
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('home.noShotsHint'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          addShot,
          const SizedBox(height: 8),
        ],
      );
    }

    final last = state.lastShot;
    final savedAt = state.savedAt;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: BigTimeDisplay(
              timeMs: last?.timeMs ?? 0,
              label: context.tr('home.total'),
            ),
          ),
        ),
        _StatsRow(
          shotCount: state.shotCount,
          firstShotMs: state.firstShotMs,
          splitMs: state.lastSplitMs,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt),
              label: Text(context.tr('home.review')),
              onPressed: state.savedStringId == null
                  ? null
                  : () => onOpen(ReviewScreen(stringId: state.savedStringId!)),
            ),
            addShot,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          savedAt == null
              ? ''
              : context.tr('home.savedAt', args: {
                  'time': DateFormat.jm().format(savedAt.toLocal()),
                }),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.shotCount,
    required this.firstShotMs,
    required this.splitMs,
  });

  final int shotCount;
  final int? firstShotMs;
  final int? splitMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Stat(label: context.tr('home.stat.shots'), value: '$shotCount'),
        _Stat(
          label: context.tr('home.stat.first'),
          value: firstShotMs == null ? '--' : formatSeconds(firstShotMs!),
        ),
        _Stat(label: context.tr('home.stat.split'), value: formatSplit(splitMs)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
