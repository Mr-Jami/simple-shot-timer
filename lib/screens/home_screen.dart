import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../models/timer_state.dart';
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/timer_provider.dart';
import '../utils/time_format.dart';
import '../widgets/big_time_display.dart';
import '../widgets/flash_overlay.dart';
import 'history_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timerProvider);
    final visualFlash =
        ref.watch(settingsProvider.select((s) => s.visualFlash));

    ref.listen(timerProvider, (prev, next) async {
      if (prev?.phase != TimerPhase.finished &&
          next.phase == TimerPhase.finished &&
          next.savedStringId != null) {
        // Refresh history list so it shows the new string.
        ref.invalidate(historyProvider);
      }
      if (next.error != null && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr(next.error!))),
        );
      }
    });

    return FlashOverlay(
      trigger: state.flashTick,
      enabled: visualFlash,
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/branding/icon.png',
              filterQuality: FilterQuality.medium,
            ),
          ),
          title: Text(context.tr('app.title')),
          actions: [
            IconButton(
              tooltip: context.tr('home.historyTooltip'),
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
            IconButton(
              tooltip: context.tr('home.settingsTooltip'),
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(child: _TimerArea(state: state)),
                const SizedBox(height: 16),
                _ControlsRow(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimerArea extends ConsumerWidget {
  const _TimerArea({required this.state});
  final TimerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    switch (state.phase) {
      case TimerPhase.idle:
        return _IdleView(settings: settings);
      case TimerPhase.countdown:
        return _CountdownView(state: state, settings: settings);
      case TimerPhase.running:
        return _RunningView(state: state);
      case TimerPhase.finished:
        return _FinishedView(state: state);
    }
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          _SettingsSummary(settings: settings),
        ],
      ),
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({required this.state, required this.settings});
  final TimerState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 16),
        _SettingsSummary(settings: settings),
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
      ],
    );
  }
}

class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <String>[
      context.tr('home.modeChip',
          args: {'mode': settings.drillMode.labelFor(context)}),
      _delayLabel(context, settings),
      if (settings.drillMode == DrillMode.par) _parLabel(context, settings),
      if (settings.drillMode == DrillMode.stage)
        _stageLabel(context, settings),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
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

  static String _delayLabel(BuildContext context, AppSettings s) {
    switch (s.delayMode) {
      case DelayMode.instant:
        return context.tr('home.delayInstant');
      case DelayMode.fixed:
        return context.tr('home.delayFixed',
            args: {'seconds': (s.fixedDelayMs / 1000).toStringAsFixed(1)});
      case DelayMode.random:
        return context.tr('home.delayRandom');
    }
  }

  static String _parLabel(BuildContext context, AppSettings s) {
    final dur = (s.parDurationMs / 1000).toStringAsFixed(1);
    final count = s.parRepeatCount;
    return count == 1
        ? context.tr('home.parSingle', args: {'duration': dur})
        : context
            .tr('home.parRepeated', args: {'duration': dur, 'count': count});
  }

  static String _stageLabel(BuildContext context, AppSettings s) {
    return context.tr('home.stage',
        args: {'duration': (s.stageDurationMs / 1000).round()});
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.state});
  final TimerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = state.lastShot;
    final displayMs = last?.timeMs ?? state.elapsedMs;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: BigTimeDisplay(
              timeMs: displayMs,
              label: last == null
                  ? context.tr('home.time')
                  : context.tr('home.last'),
            ),
          ),
        ),
        _StatsRow(
          shotCount: state.shotCount,
          firstShotMs: state.firstShotMs,
          splitMs: state.lastSplitMs,
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('home.listeningForShots'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FinishedView extends ConsumerWidget {
  const _FinishedView({required this.state});
  final TimerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final last = state.lastShot;
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
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReviewScreen(stringId: state.savedStringId!),
                        ),
                      ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(context.tr('home.addShot')),
              onPressed: () =>
                  ref.read(timerProvider.notifier).addManualShot(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('home.stringSaved'),
          style: theme.textTheme.bodyMedium,
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

class _ControlsRow extends ConsumerWidget {
  const _ControlsRow({required this.state});
  final TimerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(timerProvider.notifier);
    final inProgress = state.phase == TimerPhase.running ||
        state.phase == TimerPhase.countdown;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 96,
            child: inProgress
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: notifier.stop,
                    icon: const Icon(Icons.stop, size: 36),
                    label: Text(context.tr('home.stop')),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: notifier.start,
                    icon: const Icon(Icons.play_arrow, size: 36),
                    label: Text(context.tr('home.start')),
                  ),
          ),
        ),
        if (state.phase == TimerPhase.finished) ...[
          const SizedBox(width: 12),
          SizedBox(
            height: 96,
            width: 96,
            child: OutlinedButton(
              onPressed: notifier.reset,
              child: const Icon(Icons.refresh, size: 36),
            ),
          ),
        ],
      ],
    );
  }
}
