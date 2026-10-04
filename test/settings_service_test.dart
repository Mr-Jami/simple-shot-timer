// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

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

      await service.reset();

      final loaded = service.load();
      const defaults = AppSettings();
      expect(loaded.sensitivityPercent, defaults.sensitivityPercent);
      expect(loaded.drillMode, defaults.drillMode);
      expect(loaded.parRepeatCount, defaults.parRepeatCount);
      expect(loaded.themeMode, defaults.themeMode);
      expect(loaded.localeCode, isNull);
      // Only the drills key is left, proving every settings key was removed.
      expect(prefs.getKeys(), {'custom_drills'});
      expect(service.loadDrills().map((d) => d.name), ['Bill Drill', 'Stage 60']);
    });

    test('is a no-op on empty prefs', () async {
      await SettingsService(prefs).reset();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
