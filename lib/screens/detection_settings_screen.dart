// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../utils/slider_units.dart';
import '../widgets/settings_slider.dart';
import 'auto_configure_screen.dart';
import 'mic_test_screen.dart';

/// Calibration, one level below Settings: everything that tunes what counts
/// as a shot. Set once per gun and range, not every session.
class DetectionSettingsScreen extends ConsumerWidget {
  const DetectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.section.shotDetection'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
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
            const Divider(height: 24),
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
            const Divider(height: 24),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                context.tr('settings.beepLatencyOffsetHint'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
