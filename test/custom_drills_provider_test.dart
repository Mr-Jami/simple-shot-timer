// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/providers/custom_drills_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/settings_provider.dart';
import 'package:simple_shot_timer/services/settings_service.dart';

final _par = DrillConfig.fromSettings(const AppSettings(
  drillMode: DrillMode.par,
  parDurationMs: 2500,
  parRepeatCount: 3,
));
final _stage = DrillConfig.fromSettings(const AppSettings(
  drillMode: DrillMode.stage,
  stageDurationMs: 45000,
));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  CustomDrillsNotifier notifier() =>
      container.read(customDrillsProvider.notifier);
  List<CustomDrill> drills() => container.read(customDrillsProvider);
  List<CustomDrill> persisted() => SettingsService(prefs).loadDrills();
  SettingsNotifier settings() => container.read(settingsProvider.notifier);

  group('CustomDrillsNotifier', () {
    test('starts empty', () {
      expect(drills(), isEmpty);
    });

    test('loads what was persisted before', () async {
      await SettingsService(prefs).saveDrills([
        CustomDrill(id: 4, name: 'Earlier', config: _par),
      ]);
      expect(drills().single.name, 'Earlier');
    });

    test('add appends in creation order with increasing ids and persists',
        () async {
      await notifier().add('Par', _par);
      await notifier().add('Stage', _stage);
      expect(drills().map((d) => d.id), [1, 2]);
      expect(drills().map((d) => d.name), ['Par', 'Stage']);
      expect(persisted().map((d) => d.id), [1, 2]);
      expect(persisted().last.config, _stage);
    });

    test('add normalizes the name and ignores a blank one', () async {
      await notifier().add('   ', _par);
      expect(drills(), isEmpty);
      await notifier().add('  Bill   Drill ', _par);
      expect(drills().single.name, 'Bill Drill');
    });

    test('ids keep increasing after a delete', () async {
      await notifier().add('A', _par);
      await notifier().add('B', _stage);
      await notifier().delete(1);
      await notifier().add('C', _par);
      expect(drills().map((d) => d.id), [2, 3]);
    });

    test('findByName ignores case and whitespace and honours excludeId',
        () async {
      await notifier().add('Bill Drill', _par);
      final bill = drills().single;
      expect(notifier().findByName(' bill  drill ')?.id, bill.id);
      expect(notifier().findByName('Bill Drill', excludeId: bill.id), isNull);
      expect(notifier().findByName('Other'), isNull);
    });

    test('rename normalizes, keeps the config and persists', () async {
      await notifier().add('Old', _par);
      await notifier().rename(drills().single.id, '  New  Name ');
      expect(drills().single.name, 'New Name');
      expect(drills().single.config, _par);
      expect(persisted().single.name, 'New Name');
    });

    test('rename ignores a blank name', () async {
      await notifier().add('Keep', _par);
      await notifier().rename(drills().single.id, ' ');
      expect(drills().single.name, 'Keep');
    });

    test('overwrite replaces the config, keeping id, name and position',
        () async {
      await notifier().add('First', _par);
      await notifier().add('Second', _stage);
      final first = drills().first;
      await notifier().overwrite(first.id, _stage);
      expect(drills().first.id, first.id);
      expect(drills().first.name, 'First');
      expect(drills().first.config, _stage);
      expect(persisted().first.config, _stage);
    });

    test('delete drops the drill and persists', () async {
      await notifier().add('A', _par);
      await notifier().add('B', _stage);
      await notifier().delete(drills().first.id);
      expect(drills().map((d) => d.name), ['B']);
      expect(persisted().map((d) => d.name), ['B']);
    });
  });

  group('SettingsNotifier.applyDrill', () {
    test('changes only the drill fields and persists them', () async {
      await settings().update(
        (s) => s.copyWith(beepVolume: 0.2, sensitivityPercent: 77),
      );
      await settings().applyDrill(_par);

      final s = container.read(settingsProvider);
      expect(DrillConfig.fromSettings(s), _par);
      expect(s.beepVolume, 0.2);
      expect(s.sensitivityPercent, 77);

      final reloaded = SettingsService(prefs).load();
      expect(DrillConfig.fromSettings(reloaded), _par);
      expect(reloaded.beepVolume, 0.2);
    });
  });

  group('activeDrillProvider', () {
    test('is null without drills', () {
      expect(container.read(activeDrillProvider), isNull);
    });

    test('names the drill matching the current settings', () async {
      await notifier().add('Par', _par);
      expect(container.read(activeDrillProvider), isNull);
      await settings().applyDrill(_par);
      expect(container.read(activeDrillProvider)?.name, 'Par');
    });

    test('clears when a drill field changes, not when another setting does',
        () async {
      await notifier().add('Par', _par);
      await settings().applyDrill(_par);
      await settings().update((s) => s.copyWith(beepVolume: 0.1));
      expect(container.read(activeDrillProvider)?.name, 'Par');
      await settings().update((s) => s.copyWith(parRepeatCount: 4));
      expect(container.read(activeDrillProvider), isNull);
    });

    test('prefers the first of two identical drills', () async {
      await notifier().add('One', _stage);
      await notifier().add('Two', _stage);
      await settings().applyDrill(_stage);
      expect(container.read(activeDrillProvider)?.name, 'One');
    });

    test('follows renames and deletes', () async {
      await notifier().add('Par', _par);
      await settings().applyDrill(_par);
      final id = drills().single.id;
      await notifier().rename(id, 'Renamed');
      expect(container.read(activeDrillProvider)?.name, 'Renamed');
      await notifier().delete(id);
      expect(container.read(activeDrillProvider), isNull);
    });
  });
}
