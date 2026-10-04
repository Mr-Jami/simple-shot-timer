// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/enums.dart';
import '../providers/settings_provider.dart';
import '../utils/legal.dart';
import '../utils/slider_units.dart';
import '../widgets/settings_slider.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/tab_header.dart';
import 'detection_settings_screen.dart';

/// Duration sliders magnetically settle on half-second multiples (issue #14).
const _kDurationMagnetMs = 500;

/// Subtitle of the "Shot detection" row, so the values that matter are
/// visible without opening the page.
String _detectionSummary(BuildContext context, AppSettings s) =>
    s.bandFilterEnabled
        ? context.tr('settings.detectionSummaryBand', args: {
            'sensitivity': s.sensitivityPercent,
            'low': s.bandLowHz,
            'high': s.bandHighHz,
          })
        : context.tr('settings.detectionSummaryNoBand', args: {
            'sensitivity': s.sensitivityPercent,
          });

/// Range-day settings: what changes between drills and sessions. Calibration
/// lives one level down in [DetectionSettingsScreen]; saved drills are
/// reached from the Home app bar.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(title: context.tr('settings.title')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                SettingsSection(context.tr('settings.section.drillMode')),
                EnumChoice<DrillMode>(
                  values: DrillMode.values,
                  current: s.drillMode,
                  labelOf: (m) => m.labelFor(context),
                  onChanged: (m) =>
                      notifier.update((c) => c.copyWith(drillMode: m)),
                ),
                SettingsSection(context.tr('settings.section.startDelay')),
                EnumChoice<DelayMode>(
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
                      final max =
                          v > s.randomDelayMaxMs ? v : s.randomDelayMaxMs;
                      notifier.update((c) => c.copyWith(
                          randomDelayMinMs: v, randomDelayMaxMs: max));
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
                      final min =
                          v < s.randomDelayMinMs ? v : s.randomDelayMinMs;
                      notifier.update((c) => c.copyWith(
                          randomDelayMaxMs: v, randomDelayMinMs: min));
                    },
                  ),
                ],
                if (s.drillMode == DrillMode.par) ...[
                  SettingsSection(context.tr('settings.section.parTime')),
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
                        : context
                            .tr('settings.parBeepMany', args: {'count': v}),
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
                  SettingsSection(context.tr('settings.section.stage')),
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
                SettingsSection(context.tr('settings.section.beep')),
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
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.graphic_eq),
                  title: Text(context.tr('settings.section.shotDetection')),
                  subtitle: Text(_detectionSummary(context, s)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DetectionSettingsScreen(),
                    ),
                  ),
                ),
                SettingsSection(context.tr('settings.section.display')),
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
                SettingsSection(context.tr('settings.section.language')),
                ListTile(
                  title: Text(context.tr('settings.language')),
                  trailing: DropdownButton<String?>(
                    value: s.localeCode,
                    onChanged: (v) {
                      if (v == null) {
                        notifier
                            .update((c) => c.copyWith(clearLocaleCode: true));
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
                SettingsSection(context.tr('settings.section.history')),
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
                // Destructive, rare, and last: a text button at the end of the
                // page rather than an icon next to Back.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.restart_alt),
                      label: Text(context.tr('settings.factoryResetTooltip')),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                      onPressed: () => _confirmReset(context, ref),
                    ),
                  ),
                ),
                const _Credits(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
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
      await ref.read(settingsProvider.notifier).reset();
    }
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version;
          final suffix = version == null ? '' : '  •  v$version';
          return Column(
            children: [
              Text('$kCopyrightNotice$suffix', style: style),
              // The GPLv3 "Appropriate Legal Notices": copyright, no
              // warranty and the license texts, one tap away.
              TextButton(
                style: TextButton.styleFrom(
                  textStyle: theme.textTheme.bodySmall,
                ),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: context.tr('app.title'),
                  applicationVersion: version,
                  applicationLegalese: '$kCopyrightNotice\n\n'
                      '${context.tr('settings.legalese', args: {
                        'url': kSourceUrl,
                      })}',
                ),
                child: Text(context.tr('settings.openSource')),
              ),
            ],
          );
        },
      ),
    );
  }
}
