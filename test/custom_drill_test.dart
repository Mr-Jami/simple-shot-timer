// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/app_settings.dart';
import 'package:simple_shot_timer/models/custom_drill.dart';
import 'package:simple_shot_timer/models/drill_config.dart';
import 'package:simple_shot_timer/models/enums.dart';

CustomDrill _drill(int id, String name, {DrillMode mode = DrillMode.par}) =>
    CustomDrill(
      id: id,
      name: name,
      config: DrillConfig.fromSettings(
        AppSettings(drillMode: mode, parDurationMs: 1000 * id),
      ),
    );

void main() {
  group('CustomDrill list encoding', () {
    test('round-trips ids, names, configs and order', () {
      final drills = [
        _drill(1, 'Bill Drill'),
        _drill(7, 'El "Presidente"', mode: DrillMode.stage),
        _drill(3, '1R1 – café'),
      ];
      final decoded = CustomDrill.decodeList(CustomDrill.encodeList(drills));
      expect(decoded, hasLength(3));
      for (var i = 0; i < drills.length; i++) {
        expect(decoded[i].id, drills[i].id);
        expect(decoded[i].name, drills[i].name);
        expect(decoded[i].config, drills[i].config);
      }
    });

    test('empty input decodes to an empty list', () {
      expect(CustomDrill.decodeList(null), isEmpty);
      expect(CustomDrill.decodeList(''), isEmpty);
      expect(CustomDrill.decodeList('[]'), isEmpty);
    });

    test('corrupt input decodes to an empty list without throwing', () {
      expect(CustomDrill.decodeList('not json'), isEmpty);
      expect(CustomDrill.decodeList('{"a": 1}'), isEmpty);
      expect(CustomDrill.decodeList('42'), isEmpty);
    });

    test('skips corrupt entries and keeps the good ones', () {
      const json = '['
          '{"id": 1, "name": "Good", "drill_mode": "par"},'
          '"not a map",'
          '{"name": "No id"},'
          '{"id": "2", "name": "String id"},'
          '{"id": 3, "name": "   "},'
          '{"id": 4},'
          '{"id": 5, "name": "Also good", "par_repeat_count": "many"}'
          ']';
      final decoded = CustomDrill.decodeList(json);
      expect(decoded.map((d) => d.name), ['Good', 'Also good']);
      expect(decoded.first.config.drillMode, DrillMode.par);
      expect(
        decoded.last.config.parRepeatCount,
        DrillConfig.defaults.parRepeatCount,
      );
    });

    test('a number too large for a double is not fatal', () {
      // 1e400 decodes as infinity; toInt() on that throws, and decodeList
      // must not let a single stored value take the app down at startup.
      final decoded = CustomDrill.decodeList(
        '[{"id": 1, "name": "Huge", "par_duration_ms": 1e400}]',
      );
      expect(decoded.single.name, 'Huge');
      expect(
        decoded.single.config.parDurationMs,
        DrillConfig.defaults.parDurationMs,
      );
    });

    test('normalizes names on decode', () {
      final decoded =
          CustomDrill.decodeList('[{"id": 1, "name": "  Bill   Drill \\n"}]');
      expect(decoded.single.name, 'Bill Drill');
    });
  });

  group('CustomDrill names', () {
    test('normalizeName trims and collapses whitespace', () {
      expect(CustomDrill.normalizeName('  Bill   Drill \t'), 'Bill Drill');
      expect(CustomDrill.normalizeName('   '), '');
    });

    test('sameName ignores case and surrounding whitespace', () {
      expect(CustomDrill.sameName('Bill Drill', ' bill  drill'), isTrue);
      expect(CustomDrill.sameName('Bill Drill', 'Bill Drill 2'), isFalse);
    });
  });
}
