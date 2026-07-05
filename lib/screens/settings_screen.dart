import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../providers/settings_provider.dart';
import '../utils/slider_units.dart';
import '../widgets/settings_slider.dart';
import 'auto_configure_screen.dart';
import 'mic_test_screen.dart';

/// Duration sliders magnetically settle on half-second multiples (issue #14).
const _kDurationMagnetMs = 500;

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
              SettingsIntSlider(
                label: context.tr('settings.fixedDelay'),
                value: s.fixedDelayMs,
                min: 0,
                max: 10000,
                step: 100,
                unit: secondsFromMsUnit,
                magnet: _kDurationMagnetMs,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(fixedDelayMs: v)),
              ),
            if (s.delayMode == DelayMode.random) ...[
              SettingsIntSlider(
                label: context.tr('settings.randomMin'),
                value: s.randomDelayMinMs,
                min: 0,
                max: 10000,
                step: 100,
                unit: secondsFromMsUnit,
                magnet: _kDurationMagnetMs,
                onChanged: (v) {
                  final max = v > s.randomDelayMaxMs ? v : s.randomDelayMaxMs;
                  notifier.update((c) =>
                      c.copyWith(randomDelayMinMs: v, randomDelayMaxMs: max));
                },
              ),
              SettingsIntSlider(
                label: context.tr('settings.randomMax'),
                value: s.randomDelayMaxMs,
                min: 0,
                max: 10000,
                step: 100,
                unit: secondsFromMsUnit,
                magnet: _kDurationMagnetMs,
                onChanged: (v) {
                  final min = v < s.randomDelayMinMs ? v : s.randomDelayMinMs;
                  notifier.update((c) =>
                      c.copyWith(randomDelayMaxMs: v, randomDelayMinMs: min));
                },
              ),
            ],
            if (s.drillMode == DrillMode.par) ...[
              _Section(context.tr('settings.section.parTime')),
              SettingsIntSlider(
                label: context.tr('settings.parDuration'),
                value: s.parDurationMs,
                min: 100,
                max: 30000,
                step: 100,
                unit: secondsFromMsUnit,
                magnet: _kDurationMagnetMs,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(parDurationMs: v)),
              ),
              SettingsIntSlider(
                label: context.tr('settings.parRepeatCount'),
                value: s.parRepeatCount,
                min: AppSettings.parRepeatMin,
                max: AppSettings.parRepeatMax,
                step: 1,
                unit: countUnit,
                display: (v) => v == 1
                    ? context.tr('settings.parBeepSingle')
                    : context.tr('settings.parBeepMany', args: {'count': v}),
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(parRepeatCount: v)),
              ),
              if (s.parRepeatCount > 1)
                SettingsIntSlider(
                  label: context.tr('settings.parInterval'),
                  value: s.parIntervalMs,
                  min: 0,
                  max: 30000,
                  step: 100,
                  unit: secondsFromMsUnit,
                  magnet: _kDurationMagnetMs,
                  onChanged: (v) =>
                      notifier.update((c) => c.copyWith(parIntervalMs: v)),
                ),
            ],
            if (s.drillMode == DrillMode.stage) ...[
              _Section(context.tr('settings.section.stage')),
              SettingsIntSlider(
                label: context.tr('settings.stageDuration'),
                value: s.stageDurationMs,
                min: AppSettings.stageDurationMinMs,
                max: AppSettings.stageDurationMaxMs,
                step: 1000,
                unit: wholeSecondsFromMsUnit,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(stageDurationMs: v)),
              ),
            ],
            _Section(context.tr('settings.section.beep')),
            SettingsDoubleSlider(
              label: context.tr('settings.volume'),
              value: s.beepVolume,
              min: 0,
              max: 1,
              step: 0.05,
              unit: fractionPercentUnit,
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
            SettingsIntSlider(
              label: context.tr('settings.beepLatencyOffset'),
              value: s.audioLatencyOffsetMs,
              min: AppSettings.audioLatencyOffsetMinMs,
              max: AppSettings.audioLatencyOffsetMaxMs,
              step: 10,
              unit: millisecondsUnit,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(audioLatencyOffsetMs: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                context.tr('settings.beepLatencyOffsetHint'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            _Section(context.tr('settings.section.shotDetection')),
            SettingsIntSlider(
              label: context.tr('settings.sensitivity'),
              value: s.sensitivityPercent,
              min: 0,
              max: 100,
              step: 1,
              unit: percentUnit,
              onChanged: (v) =>
                  notifier.update((c) => c.copyWith(sensitivityPercent: v)),
            ),
            SettingsIntSlider(
              label: context.tr('settings.echoFilter'),
              value: s.echoFilterMs,
              min: 20,
              max: 300,
              step: 10,
              unit: millisecondsUnit,
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
              SettingsIntSlider(
                label: context.tr('settings.bandLow'),
                value: s.bandLowHz,
                min: AppSettings.bandLowMinHz,
                max: AppSettings.bandLowMaxHz,
                step: 50,
                unit: hertzUnit,
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
              SettingsIntSlider(
                label: context.tr('settings.bandHigh'),
                value: s.bandHighHz,
                min: AppSettings.bandHighMinHz,
                max: AppSettings.bandHighMaxHz,
                step: 100,
                unit: hertzUnit,
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
            ListTile(
              leading: const Icon(Icons.auto_fix_high),
              title: Text(context.tr('settings.autoConfigTitle')),
              subtitle: Text(context.tr('settings.autoConfigSubtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AutoConfigureScreen()),
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
            SettingsIntSlider(
              label: context.tr('settings.historyKeepMostRecent'),
              value: s.historyCap,
              min: AppSettings.historyCapMin,
              max: AppSettings.historyCapMax,
              step: 50,
              unit: countUnit,
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

