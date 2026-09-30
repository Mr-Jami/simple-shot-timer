import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';

/// Every drill field differs from the defaults so a copy that forgot one
/// would show up in the assertions below.
const _drill = AppSettings(
  drillMode: DrillMode.par,
  delayMode: DelayMode.fixed,
  fixedDelayMs: 3300,
  randomDelayMinMs: 700,
  randomDelayMaxMs: 5200,
  parDurationMs: 1800,
  parRepeatCount: 4,
  parIntervalMs: 2500,
  stageDurationMs: 90000,
);

/// Non-drill fields set away from their defaults, so `applyTo` can be checked
/// for leaving them alone.
const _other = AppSettings(
  sensitivityPercent: 42,
  echoFilterMs: 120,
  bandFilterEnabled: false,
  bandLowHz: 450,
  bandHighHz: 8000,
  beepVolume: 0.35,
  audioLatencyOffsetMs: 80,
  keepScreenAwake: false,
  visualFlash: false,
  hapticOnBeep: true,
  themeMode: AppThemeMode.dark,
  historyCap: 100,
  localeCode: 'de',
);

/// One mutation per drill field, used to prove each one takes part in
/// equality and in `applyTo`.
final _singleFieldEdits = <String, AppSettings Function(AppSettings)>{
  'drillMode': (s) => s.copyWith(drillMode: DrillMode.stage),
  'delayMode': (s) => s.copyWith(delayMode: DelayMode.instant),
  'fixedDelayMs': (s) => s.copyWith(fixedDelayMs: s.fixedDelayMs + 100),
  'randomDelayMinMs': (s) =>
      s.copyWith(randomDelayMinMs: s.randomDelayMinMs + 100),
  'randomDelayMaxMs': (s) =>
      s.copyWith(randomDelayMaxMs: s.randomDelayMaxMs + 100),
  'parDurationMs': (s) => s.copyWith(parDurationMs: s.parDurationMs + 100),
  'parRepeatCount': (s) => s.copyWith(parRepeatCount: s.parRepeatCount + 1),
  'parIntervalMs': (s) => s.copyWith(parIntervalMs: s.parIntervalMs + 100),
  'stageDurationMs': (s) =>
      s.copyWith(stageDurationMs: s.stageDurationMs + 1000),
};

void main() {
  group('DrillConfig.fromSettings', () {
    test('copies every drill field', () {
      final c = DrillConfig.fromSettings(_drill);
      expect(c.drillMode, DrillMode.par);
      expect(c.delayMode, DelayMode.fixed);
      expect(c.fixedDelayMs, 3300);
      expect(c.randomDelayMinMs, 700);
      expect(c.randomDelayMaxMs, 5200);
      expect(c.parDurationMs, 1800);
      expect(c.parRepeatCount, 4);
      expect(c.parIntervalMs, 2500);
      expect(c.stageDurationMs, 90000);
    });

    test('defaults equal a fresh AppSettings', () {
      expect(
        DrillConfig.defaults,
        DrillConfig.fromSettings(const AppSettings()),
      );
    });
  });

  group('DrillConfig.applyTo', () {
    test('leaves every non-drill field untouched', () {
      final applied = DrillConfig.fromSettings(_drill).applyTo(_other);
      expect(applied.sensitivityPercent, _other.sensitivityPercent);
      expect(applied.echoFilterMs, _other.echoFilterMs);
      expect(applied.bandFilterEnabled, _other.bandFilterEnabled);
      expect(applied.bandLowHz, _other.bandLowHz);
      expect(applied.bandHighHz, _other.bandHighHz);
      expect(applied.beepVolume, _other.beepVolume);
      expect(applied.audioLatencyOffsetMs, _other.audioLatencyOffsetMs);
      expect(applied.keepScreenAwake, _other.keepScreenAwake);
      expect(applied.visualFlash, _other.visualFlash);
      expect(applied.hapticOnBeep, _other.hapticOnBeep);
      expect(applied.themeMode, _other.themeMode);
      expect(applied.historyCap, _other.historyCap);
      expect(applied.localeCode, _other.localeCode);
    });

    test('each drill field is applied', () {
      for (final entry in _singleFieldEdits.entries) {
        final edited = entry.value(_drill);
        final applied = DrillConfig.fromSettings(edited).applyTo(_drill);
        expect(
          DrillConfig.fromSettings(applied),
          DrillConfig.fromSettings(edited),
          reason: '${entry.key} was not applied',
        );
      }
    });
  });

  group('DrillConfig equality', () {
    test('ignores non-drill settings', () {
      final a = DrillConfig.fromSettings(_drill);
      final b = DrillConfig.fromSettings(
        DrillConfig.fromSettings(_drill).applyTo(_other),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any single drill field differs', () {
      final base = DrillConfig.fromSettings(_drill);
      for (final entry in _singleFieldEdits.entries) {
        final edited = DrillConfig.fromSettings(entry.value(_drill));
        expect(edited, isNot(base), reason: '${entry.key} ignored by ==');
      }
    });
  });

  group('DrillConfig serialization', () {
    test('survives a JSON round trip', () {
      final original = DrillConfig.fromSettings(_drill);
      final json = jsonEncode(original.toMap());
      final decoded = DrillConfig.fromMap(
        Map<String, Object?>.from(jsonDecode(json) as Map),
      );
      expect(decoded, original);
    });

    test('round-trips every enum value', () {
      for (final mode in DrillMode.values) {
        for (final delay in DelayMode.values) {
          final c = DrillConfig.fromSettings(
            AppSettings(drillMode: mode, delayMode: delay),
          );
          expect(DrillConfig.fromMap(c.toMap()), c);
        }
      }
    });

    test('empty map yields the defaults', () {
      expect(DrillConfig.fromMap(const {}), DrillConfig.defaults);
    });

    test('unknown enum names fall back to the defaults', () {
      final c = DrillConfig.fromMap(const {
        'drill_mode': 'bogus',
        'delay_mode': 42,
      });
      expect(c.drillMode, DrillConfig.defaults.drillMode);
      expect(c.delayMode, DrillConfig.defaults.delayMode);
    });

    test('non-numeric values fall back to the defaults', () {
      final c = DrillConfig.fromMap(const {'par_duration_ms': 'soon'});
      expect(c.parDurationMs, DrillConfig.defaults.parDurationMs);
    });

    test('non-finite numbers fall back instead of throwing', () {
      final c = DrillConfig.fromMap(const {
        'par_duration_ms': double.infinity,
        'stage_duration_ms': double.nan,
      });
      expect(c.parDurationMs, DrillConfig.defaults.parDurationMs);
      expect(c.stageDurationMs, DrillConfig.defaults.stageDurationMs);
    });
  });
}
