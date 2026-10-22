// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The real schema and migrations, run on the desktop through sqflite's FFI
/// backend. Old databases are built from the schemas as they shipped.
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('db_migration_test');
  });
  tearDown(() => dir.delete(recursive: true));

  String path(String name) => '${dir.path}/$name.db';

  // Version 1 as it shipped, before per-cycle shots (v2) and par configs (v3).
  const v1Strings = '''
    CREATE TABLE strings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at TEXT NOT NULL,
      drill_mode TEXT NOT NULL,
      delay_mode TEXT NOT NULL,
      delay_used_ms INTEGER NOT NULL,
      pars_json TEXT,
      label TEXT,
      notes TEXT,
      penalty_ms INTEGER NOT NULL DEFAULT 0
    )''';
  const v1Shots = '''
    CREATE TABLE shots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      string_id INTEGER NOT NULL,
      idx INTEGER NOT NULL,
      time_ms INTEGER NOT NULL,
      manual INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(string_id) REFERENCES strings(id) ON DELETE CASCADE
    )''';
  const indexes = [
    'CREATE INDEX idx_shots_string ON shots(string_id, idx)',
    'CREATE INDEX idx_strings_created ON strings(created_at DESC)',
  ];

  Future<void> createOld(String file, int version, List<String> ddl) async {
    final db = await factory.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          for (final statement in ddl) {
            await db.execute(statement);
          }
        },
      ),
    );
    await db.insert('strings', {
      'created_at': '2026-03-01T10:00:00.000',
      'drill_mode': 'par',
      'delay_mode': 'fixed',
      'delay_used_ms': 2500,
      'pars_json': '[{"enabled":true,"durationMs":3000}]',
      'label': 'Bill drill',
      'penalty_ms': 0,
      if (version >= 3) 'par_repeat_count': 3,
    });
    for (var i = 0; i < 2; i++) {
      await db.insert('shots', {
        'string_id': 1,
        'idx': i,
        'time_ms': 800 + 300 * i,
        'manual': i,
        if (version >= 2) 'cycle_index': 2,
      });
    }
    await db.close();
  }

  Future<List<Map<String, Object?>>> tableInfo(String file, String table) async {
    final db = await factory.openDatabase(file);
    try {
      return await db.rawQuery('PRAGMA table_info($table)');
    } finally {
      await db.close();
    }
  }

  for (final (version, ddl) in [
    (1, [v1Strings, v1Shots, ...indexes]),
    (
      3,
      [
        v1Strings.replaceFirst(
          'penalty_ms INTEGER NOT NULL DEFAULT 0',
          'penalty_ms INTEGER NOT NULL DEFAULT 0, '
              'par_repeat_count INTEGER, par_interval_ms INTEGER',
        ),
        v1Shots.replaceFirst(
          'manual INTEGER NOT NULL DEFAULT 0,',
          'manual INTEGER NOT NULL DEFAULT 0, '
              'cycle_index INTEGER NOT NULL DEFAULT 1,',
        ),
        ...indexes,
      ]
    ),
  ]) {
    group('upgrading a version $version database', () {
      test('keeps its strings as live strings with their shots', () async {
        final file = path('v$version');
        await createOld(file, version, ddl);

        final service = await DatabaseService.openAt(file, factory: factory);
        final s = (await service.getString(1))!;
        await service.close();

        expect(s.source, StringSource.live);
        expect(s.isVideo, isFalse);
        expect(s.videoStartMs, isNull);
        expect(s.videoDurationMs, isNull);
        expect(s.videoRecordedAt, isNull);
        expect(s.drillMode, DrillMode.par);
        expect(s.label, 'Bill drill');
        expect(s.parRepeatCount, version >= 3 ? 3 : null);
        expect(s.shots.map((x) => x.timeMs), [800, 1100]);
        expect(s.shots.map((x) => x.manual), [false, true]);
        expect(s.shots.map((x) => x.cycleIndex), version >= 2 ? [2, 2] : [1, 1]);
      });

      test('ends with the same tables as a fresh install', () async {
        final old = path('v$version');
        await createOld(old, version, ddl);
        await (await DatabaseService.openAt(old, factory: factory)).close();
        final fresh = path('fresh');
        await (await DatabaseService.openAt(fresh, factory: factory)).close();

        for (final table in ['strings', 'shots']) {
          expect(await tableInfo(old, table), await tableInfo(fresh, table),
              reason: table);
        }
      });
    });
  }

  group('a video string', () {
    final recorded = DateTime.utc(2026, 10, 20, 9, 15, 30);
    TimerString video({int? id}) => TimerString(
          id: id,
          createdAt: DateTime(2026, 10, 23, 14),
          drillMode: DrillMode.standard,
          delayMode: DelayMode.instant,
          delayUsedMs: 0,
          pars: const [],
          shots: [
            Shot(index: 0, timeMs: 1720),
            Shot(index: 1, timeMs: 2060, manual: true),
          ],
          source: StringSource.video,
          videoStartMs: 4788,
          videoDurationMs: 24634,
          videoRecordedAt: recorded,
        );

    test('round-trips through the database', () async {
      final service = await DatabaseService.openAt(path('video'), factory: factory);
      final saved = await service.insertString(video(), historyCap: 500);
      final read = (await service.getString(saved.id!))!;
      await service.close();

      expect(read.isVideo, isTrue);
      expect(read.videoStartMs, 4788);
      expect(read.videoDurationMs, 24634);
      expect(read.videoRecordedAt, recorded);
      expect(read.shots.map((s) => (s.timeMs, s.manual)),
          [(1720, false), (2060, true)]);
    });

    test('updateVideoString rewrites START, meta and shots at once', () async {
      final service = await DatabaseService.openAt(path('update'), factory: factory);
      final saved = await service.insertString(
        video().copyWith(label: 'El Presidente'),
        historyCap: 500,
      );
      await service.updateVideoString(TimerString(
        id: saved.id,
        createdAt: saved.createdAt,
        drillMode: DrillMode.standard,
        delayMode: DelayMode.instant,
        delayUsedMs: 0,
        pars: const [],
        shots: [Shot(index: 0, timeMs: 1500)],
        penaltyMs: 2000,
        source: StringSource.video,
        videoStartMs: 5000,
      ));
      final read = (await service.getString(saved.id!))!;
      await service.close();

      expect(read.label, isNull);
      expect(read.penaltyMs, 2000);
      expect(read.videoStartMs, 5000);
      expect(read.shots.map((s) => s.timeMs), [1500]);
      // Not part of an edit: the clip's length and date stay as saved.
      expect(read.videoDurationMs, 24634);
      expect(read.videoRecordedAt, recorded);
    });
  });
}
