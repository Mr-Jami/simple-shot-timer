import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../providers/settings_provider.dart';
import 'mic_test_screen.dart';

String _formatHz(int hz) =>
    hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '$hz Hz';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings.title')),
        actions: [
          IconButton(
            tooltip: context.tr('settings.factoryResetTooltip'),
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(context.tr('settings.resetConfirmTitle')),
                  content: Text(context.tr('settings.resetConfirmBody')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(context.tr('common.cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(context.tr('common.reset')),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await notifier.reset();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _Section(context.tr('settings.section.drillMode')),
            _EnumPicker<DrillMode>(
              values: DrillMode.values,
              current: s.drillMode,
              labelOf: (m) => m.labelFor(context),
              onChanged: (m) =>
                  notifier.update((c) => c.copyWith(drillMode: m)),
            ),
            _Section(context.tr('settings.section.startDelay')),
            _EnumPicker<DelayMode>(
              values: DelayMode.values,
              current: s.delayMode,
              labelOf: (m) => m.labelFor(context),
              onChanged: (m) =>
                  notifier.update((c) => c.copyWith(delayMode: m)),
            ),
            if (s.delayMode == DelayMode.fixed)
              _SecondsSlider(
                label: context.tr('settings.fixedDelay'),
                valueMs: s.fixedDelayMs,
                minMs: 0,
                maxMs: 10000,
                stepMs: 100,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(fixedDelayMs: v)),
              ),
            if (s.delayMode == DelayMode.random) ...[
              _SecondsSlider(
                label: context.tr('settings.randomMin'),
                valueMs: s.randomDelayMinMs,
                minMs: 0,
                maxMs: 10000,
                stepMs: 100,
                onChanged: (v) {
                  final max = v > s.randomDelayMaxMs ? v : s.randomDelayMaxMs;
                  notifier.update((c) =>
                      c.copyWith(randomDelayMinMs: v, randomDelayMaxMs: max));
                },
              ),
              _SecondsSlider(
                label: context.tr('settings.randomMax'),
                valueMs: s.randomDelayMaxMs,
                minMs: 0,
                maxMs: 10000,
                stepMs: 100,
                onChanged: (v) {
                  final min = v < s.randomDelayMinMs ? v : s.randomDelayMinMs;
                  notifier.update((c) =>
                      c.copyWith(randomDelayMaxMs: v, randomDelayMinMs: min));
                },
              ),
            ],
            if (s.drillMode == DrillMode.par) ...[
              _Section(context.tr('settings.section.parTime')),
              _SecondsSlider(
                label: context.tr('settings.parDuration'),
                valueMs: s.parDurationMs,
                minMs: 100,
                maxMs: 30000,
                stepMs: 100,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(parDurationMs: v)),
              ),
              _IntSlider(
                label: context.tr('settings.parRepeatCount'),
                value: s.parRepeatCount,
                min: AppSettings.parRepeatMin,
                max: AppSettings.parRepeatMax,
                step: 1,
                display: (v) => v == 1
                    ? context.tr('settings.parBeepSingle')
                    : context.tr('settings.parBeepMany', args: {'count': v}),
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(parRepeatCount: v)),
              ),
              if (s.parRepeatCount > 1)
                _SecondsSlider(
                  label: context.tr('settings.parInterval'),
                  valueMs: s.parIntervalMs,
                  minMs: 0,
                  maxMs: 30000,
                  stepMs: 100,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(parIntervalMs: v)),
                ),
            ],
            if (s.drillMode == DrillMode.stage) ...[
              _Section(context.tr('settings.section.stage')),
              _IntSlider(
                label: context.tr('settings.stageDuration'),
                value: s.stageDurationMs,
                min: AppSettings.stageDurationMinMs,
                max: AppSettings.stageDurationMaxMs,
                step: 1000,
                display: (v) => '${(v / 1000).round()}s',
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(stageDurationMs: v)),
              ),
            ],
            _Section(context.tr('settings.section.beep')),
            _DoubleSlider(
              label: context.tr('settings.volume'),
              value: s.beepVolume,
              min: 0,
              max: 1,
              divisions: 20,
              display: (v) => '${(v * 100).round()}%',
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(beepVolume: v)),
            ),
            SwitchListTile(
              title: Text(context.tr('settings.visualFlash')),
              value: s.visualFlash,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(visualFlash: v)),
            ),
            SwitchListTile(
              title: Text(context.tr('settings.hapticOnBeep')),
              value: s.hapticOnBeep,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(hapticOnBeep: v)),
            ),
            _Section(context.tr('settings.section.shotDetection')),
            _IntSlider(
              label: context.tr('settings.sensitivity'),
              value: s.sensitivityPercent,
              min: 0,
              max: 100,
              step: 1,
              display: (v) => '$v%',
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(sensitivityPercent: v)),
            ),
            _IntSlider(
              label: context.tr('settings.echoFilter'),
              value: s.echoFilterMs,
              min: 20,
              max: 300,
              step: 10,
              display: (v) => '${v}ms',
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(echoFilterMs: v)),
            ),
            SwitchListTile(
              title: Text(context.tr('settings.bandFilter')),
              subtitle: Text(context.tr('settings.bandFilterHint')),
              value: s.bandFilterEnabled,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(bandFilterEnabled: v)),
            ),
            if (s.bandFilterEnabled) ...[
              _IntSlider(
                label: context.tr('settings.bandLow'),
                value: s.bandLowHz,
                min: AppSettings.bandLowMinHz,
                max: AppSettings.bandLowMaxHz,
                step: 50,
                display: _formatHz,
                onChanged: (v) {
                  // Keep low strictly below high, with at least 500 Hz of
                  // separation so the bandpass actually has a passband.
                  final high = v + 500 > s.bandHighHz ? v + 500 : s.bandHighHz;
                  notifier.update((c) => c.copyWith(
                        bandLowHz: v,
                        bandHighHz: high.clamp(
                          AppSettings.bandHighMinHz,
                          AppSettings.bandHighMaxHz,
                        ),
                      ));
                },
              ),
              _IntSlider(
                label: context.tr('settings.bandHigh'),
                value: s.bandHighHz,
                min: AppSettings.bandHighMinHz,
                max: AppSettings.bandHighMaxHz,
                step: 100,
                display: _formatHz,
                onChanged: (v) {
                  final low = v - 500 < s.bandLowHz ? v - 500 : s.bandLowHz;
                  notifier.update((c) => c.copyWith(
                        bandHighHz: v,
                        bandLowHz: low.clamp(
                          AppSettings.bandLowMinHz,
                          AppSettings.bandLowMaxHz,
                        ),
                      ));
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.mic),
              title: Text(context.tr('settings.testMicTitle')),
              subtitle: Text(context.tr('settings.testMicSubtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MicTestScreen()),
              ),
            ),
            _Section(context.tr('settings.section.display')),
            SwitchListTile(
              title: Text(context.tr('settings.keepScreenAwake')),
              value: s.keepScreenAwake,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(keepScreenAwake: v)),
            ),
            ListTile(
              title: Text(context.tr('settings.theme')),
              trailing: DropdownButton<AppThemeMode>(
                value: s.themeMode,
                onChanged: (v) {
                  if (v != null) {
                    notifier.update((c) => c.copyWith(themeMode: v));
                  }
                },
                items: [
                  for (final m in AppThemeMode.values)
                    DropdownMenuItem(
                        value: m, child: Text(m.labelFor(context))),
                ],
              ),
            ),
            _Section(context.tr('settings.section.language')),
            ListTile(
              title: Text(context.tr('settings.language')),
              trailing: DropdownButton<String?>(
                value: s.localeCode,
                onChanged: (v) {
                  if (v == null) {
                    notifier.update((c) => c.copyWith(clearLocaleCode: true));
                  } else {
                    notifier.update((c) => c.copyWith(localeCode: v));
                  }
                },
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.tr('settings.languageSystem')),
                  ),
                  for (final l in kSupportedAppLocales)
                    DropdownMenuItem<String?>(
                      value: l.code,
                      child: Text(l.displayName),
                    ),
                ],
              ),
            ),
            _Section(context.tr('settings.section.history')),
            _IntSlider(
              label: context.tr('settings.historyKeepMostRecent'),
              value: s.historyCap,
              min: AppSettings.historyCapMin,
              max: AppSettings.historyCapMax,
              step: 50,
              display: (v) => context
                  .tr('settings.historyStringsValue', args: {'count': v}),
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(historyCap: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                context.tr('settings.historyHint'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const _Credits(),
          ],
        ),
      ),
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 1,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Center(
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final version = snapshot.data?.version;
            final suffix = version == null ? '' : '  •  v$version';
            return Text(
              '© ${DateTime.now().year} Jami IT$suffix',
              style: style,
            );
          },
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _EnumPicker<T extends Enum> extends StatelessWidget {
  const _EnumPicker({
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T current;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(labelOf(v)),
              selected: v == current,
              onSelected: (_) => onChanged(v),
            ),
        ],
      ),
    );
  }
}

class _IntSlider extends StatelessWidget {
  const _IntSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int) display;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / step).round();
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(label)),
          Text(display(value)),
        ],
      ),
      subtitle: Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: divisions <= 0 ? null : divisions,
        onChanged: (v) {
          final snapped = (v / step).round() * step;
          onChanged(snapped.clamp(min, max));
        },
      ),
    );
  }
}

class _SecondsSlider extends StatelessWidget {
  const _SecondsSlider({
    required this.label,
    required this.valueMs,
    required this.minMs,
    required this.maxMs,
    required this.stepMs,
    required this.onChanged,
  });

  final String label;
  final int valueMs;
  final int minMs;
  final int maxMs;
  final int stepMs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _IntSlider(
      label: label,
      value: valueMs,
      min: minMs,
      max: maxMs,
      step: stepMs,
      display: (v) => '${(v / 1000).toStringAsFixed(1)}s',
      onChanged: onChanged,
    );
  }
}

class _DoubleSlider extends StatelessWidget {
  const _DoubleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(label)),
          Text(display(value)),
        ],
      ),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}
