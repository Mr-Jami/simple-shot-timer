// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/services/settings_service.dart';

final _drills = [
  CustomDrill(
    id: 1,
    name: 'Bill Drill',
    config: DrillConfig.fromSettings(
      const AppSettings(drillMode: DrillMode.par, parDurationMs: 2000),
    ),
  ),
  CustomDrill(
    id: 2,
    name: 'Stage 60',
    config: DrillConfig.fromSettings(
      const AppSettings(drillMode: DrillMode.stage, stageDurationMs: 60000),
    ),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('SettingsService custom drills', () {
    test('drills survive a restart (fresh service over the same prefs)',
        () async {
      await SettingsService(prefs).saveDrills(_drills);
      final loaded = SettingsService(prefs).loadDrills();
      expect(loaded, hasLength(2));
      for (var i = 0; i < _drills.length; i++) {
        expect(loaded[i].id, _drills[i].id);
        expect(loaded[i].name, _drills[i].name);
        expect(loaded[i].config, _drills[i].config);
      }
    });

    test('a drill stored without a sensitivity loads with the one in use',
        () async {
      await prefs.setInt('sensitivity_percent', 33);
      await prefs.setString('custom_drills', '[{"id": 1, "name": "Old"}]');
      expect(
        SettingsService(prefs).loadDrills().single.config.sensitivityPercent,
        33,
      );
    });
  });

  group('SettingsService.migrateDrills', () {
    List<Object?> stored() =>
        jsonDecode(prefs.getString('custom_drills')!) as List<Object?>;

    test('gives drills without a sensitivity the one in use', () async {
      await prefs.setInt('sensitivity_percent', 33);
      await prefs.setString(
        'custom_drills',
        '['
            '{"id": 1, "name": "Old", "drill_mode": "par"},'
            '{"id": 2, "name": "New", "sensitivity_percent": 8},'
            '{"id": 3, "name": "Future", "wind_hold": [1, 2]},'
            '{"name": "No id"},'
            '"not a map"'
            ']',
      );

      await SettingsService(prefs).migrateDrills();

      expect(stored(), [
        {'id': 1, 'name': 'Old', 'drill_mode': 'par', 'sensitivity_percent': 33},
        // A stored sensitivity is kept.
        {'id': 2, 'name': 'New', 'sensitivity_percent': 8},
        // So is a key this version doesn't know.
        {
          'id': 3,
          'name': 'Future',
          'wind_hold': [1, 2],
          'sensitivity_percent': 33,
        },
        // Entries the decoder skips are still there.
        {'name': 'No id', 'sensitivity_percent': 33},
        'not a map',
      ]);
      expect(prefs.getInt('custom_drills_version'), 2);
      expect(
        SettingsService(prefs)
            .loadDrills()
            .map((d) => d.config.sensitivityPercent),
        [33, 8, 33],
      );
    });

    test('a later sensitivity change does not reach upgraded drills',
        () async {
      await prefs.setInt('sensitivity_percent', 33);
      await prefs.setString('custom_drills', '[{"id": 1, "name": "Old"}]');
      final service = SettingsService(prefs);
      await service.migrateDrills();
      final before = prefs.getString('custom_drills');

      await prefs.setInt('sensitivity_percent', 70);
      await service.migrateDrills();
      // Even a forced second run (as if the version write had been lost)
      // only fills in what is missing, which is nothing now.
      await prefs.remove('custom_drills_version');
      await service.migrateDrills();

      expect(prefs.getString('custom_drills'), before);
      expect(service.loadDrills().single.config.sensitivityPercent, 33);
      expect(prefs.getInt('custom_drills_version'), 2);
    });

    test('uses the default sensitivity when none was ever saved', () async {
      await prefs.setString('custom_drills', '[{"id": 1, "name": "Old"}]');
      await SettingsService(prefs).migrateDrills();
      expect(
        (stored().single as Map)['sensitivity_percent'],
        const AppSettings().sensitivityPercent,
      );
    });

    test('without drills only the version is written', () async {
      await SettingsService(prefs).migrateDrills();
      expect(prefs.getKeys(), {'custom_drills_version'});
      expect(prefs.getInt('custom_drills_version'), 2);
    });

    test('leaves a value that is not a JSON list alone', () async {
      for (final value in ['not json', '{"id": 1, "name": "Map"}', '42']) {
        await prefs.remove('custom_drills_version');
        await prefs.setString('custom_drills', value);
        await SettingsService(prefs).migrateDrills();
        expect(prefs.getString('custom_drills'), value);
        expect(prefs.getInt('custom_drills_version'), 2);
      }
    });

    test('leaves a list it cannot write back alone', () async {
      // 1e400 decodes as infinity, which JSON has no way to encode.
      const value = '[{"id": 1, "name": "Huge", "par_duration_ms": 1e400}]';
      await prefs.setString('custom_drills', value);
      await SettingsService(prefs).migrateDrills();
      expect(prefs.getString('custom_drills'), value);
      expect(prefs.getInt('custom_drills_version'), 2);
    });

    test('runs again next start when the drills could not be written',
        () async {
      const value = '[{"id": 1, "name": "Old"}]';
      await prefs.setString('custom_drills', value);
      await SettingsService(_RejectedStrings(prefs)).migrateDrills();
      // No version: the next start tries again.
      expect(prefs.getKeys(), {'custom_drills'});
      expect(prefs.getString('custom_drills'), value);
    });

    test('does nothing once the version is current', () async {
      const value = '[{"id": 1, "name": "Old"}]';
      await prefs.setInt('custom_drills_version', 2);
      await prefs.setString('custom_drills', value);
      await SettingsService(prefs).migrateDrills();
      expect(prefs.getString('custom_drills'), value);
    });
  });

  group('SettingsService beep latency estimate', () {
    test('defaults when absent and round-trips when saved', () async {
      final service = SettingsService(prefs);
      expect(
        service.load().beepLatencyEstimateMs,
        AppSettings.defaultBeepLatencyEstimateMs,
      );
      await service.save(const AppSettings(beepLatencyEstimateMs: 123));
      expect(SettingsService(prefs).load().beepLatencyEstimateMs, 123);
    });
  });

  group('SettingsService video export choices', () {
    test('default to splits, top left, end card, the string; round-trip',
        () async {
      final service = SettingsService(prefs);
      final loaded = service.load();
      expect(
          (
            loaded.hudStyle,
            loaded.hudCorner,
            loaded.hudEndCard,
            loaded.exportWholeVideo
          ),
          (HudStyle.splits, HudCorner.topLeft, true, false));
      await service.save(const AppSettings(
        hudStyle: HudStyle.full,
        hudCorner: HudCorner.bottomRight,
        hudEndCard: false,
        exportWholeVideo: true,
      ));
      final again = SettingsService(prefs).load();
      expect(
          (
            again.hudStyle,
            again.hudCorner,
            again.hudEndCard,
            again.exportWholeVideo
          ),
          (HudStyle.full, HudCorner.bottomRight, false, true));
    });
  });

  group('SettingsService.reset', () {
    test('restores every setting to its default but keeps the drills',
        () async {
      final service = SettingsService(prefs);
      await service.save(const AppSettings(
        sensitivityPercent: 5,
        drillMode: DrillMode.stage,
        parRepeatCount: 7,
        themeMode: AppThemeMode.dark,
        localeCode: 'fr',
      ));
      await service.saveDrills(_drills);
      await service.setEncoderColorFix(true);

      await service.reset();

      final loaded = service.load();
      const defaults = AppSettings();
      expect(loaded.sensitivityPercent, defaults.sensitivityPercent);
      expect(loaded.drillMode, defaults.drillMode);
      expect(loaded.parRepeatCount, defaults.parRepeatCount);
      expect(loaded.themeMode, defaults.themeMode);
      expect(loaded.localeCode, isNull);
      expect(service.encoderColorFix, isNull);
      // Only the drills key is left, proving every settings key was removed.
      expect(prefs.getKeys(), {'custom_drills'});
      expect(service.loadDrills().map((d) => d.name), ['Bill Drill', 'Stage 60']);
    });

    test('keeps the drills version, so the upgrade does not run again',
        () async {
      final service = SettingsService(prefs);
      await service.save(const AppSettings(sensitivityPercent: 5));
      await service.saveDrills(_drills);
      await service.migrateDrills();

      await service.reset();

      expect(prefs.getKeys(), {'custom_drills', 'custom_drills_version'});
      expect(prefs.getInt('custom_drills_version'), 2);
      expect(service.load().sensitivityPercent,
          const AppSettings().sensitivityPercent);
    });

    test('is a no-op on empty prefs', () async {
      await SettingsService(prefs).reset();
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('SettingsService.clear', () {
    test('removes every setting and the drills', () async {
      final service = SettingsService(prefs);
      await service.save(const AppSettings(
        sensitivityPercent: 5,
        themeMode: AppThemeMode.dark,
        localeCode: 'fr',
      ));
      await service.saveDrills(_drills);
      await service.migrateDrills();
      expect(prefs.getKeys(), contains('custom_drills_version'));

      await service.clear();

      expect(prefs.getKeys(), isEmpty);
      expect(service.loadDrills(), isEmpty);
      expect(service.load().sensitivityPercent,
          const AppSettings().sensitivityPercent);
    });
  });
}

/// Prefs that reject string writes, as when the platform store fails.
class _RejectedStrings implements SharedPreferences {
  _RejectedStrings(this._inner);

  final SharedPreferences _inner;

  @override
  Object? get(String key) => _inner.get(key);

  @override
  int? getInt(String key) => _inner.getInt(key);

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Future<bool> setInt(String key, int value) => _inner.setInt(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
