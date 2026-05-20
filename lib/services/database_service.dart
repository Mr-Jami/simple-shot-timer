import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/shot.dart';
import '../models/timer_string.dart';

class DatabaseService {
  DatabaseService._(this._db);

  final Database _db;

  static Future<DatabaseService> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'simple_shot_timer.db');
    final db = await openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _onUpgrade,
    );
    return DatabaseService._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE strings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        drill_mode TEXT NOT NULL,
        delay_mode TEXT NOT NULL,
        delay_used_ms INTEGER NOT NULL,
        pars_json TEXT,
        label TEXT,
        notes TEXT,
        penalty_ms INTEGER NOT NULL DEFAULT 0,
        par_repeat_count INTEGER,
        par_interval_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE shots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        string_id INTEGER NOT NULL,
        idx INTEGER NOT NULL,
        time_ms INTEGER NOT NULL,
        manual INTEGER NOT NULL DEFAULT 0,
        cycle_index INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(string_id) REFERENCES strings(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_shots_string ON shots(string_id, idx)',
    );
    await db.execute(
      'CREATE INDEX idx_strings_created ON strings(created_at DESC)',
    );
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Per-cycle shot tagging for par-repeat runs (issue #5). Existing rows
      // default to cycle 1 since the old schema couldn't differentiate.
      await db.execute(
        'ALTER TABLE shots ADD COLUMN cycle_index INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 3) {
      // Capture the full par config per run (issue #6). Existing rows stay
      // NULL — they're rendered without the new chips in the review header.
      await db.execute('ALTER TABLE strings ADD COLUMN par_repeat_count INTEGER');
      await db.execute('ALTER TABLE strings ADD COLUMN par_interval_ms INTEGER');
    }
  }

  Future<TimerString> insertString(TimerString s, {required int historyCap}) async {
    return _db.transaction((txn) async {
      final id = await txn.insert('strings', s.toMap()..remove('id'));
      for (final shot in s.shots) {
        await txn.insert('shots', shot.copyWith(stringId: id).toMap()..remove('id'));
      }
      await _pruneToCap(txn, historyCap);
      final updatedShots = await _readShots(txn, id);
      final row = (await txn.query('strings', where: 'id = ?', whereArgs: [id])).first;
      return TimerString.fromMap(row, shots: updatedShots);
    });
  }

  Future<void> updateStringMeta(
    int id, {
    String? label,
    String? notes,
    int? penaltyMs,
  }) async {
    final updates = <String, Object?>{};
    if (label != null) updates['label'] = label;
    if (notes != null) updates['notes'] = notes;
    if (penaltyMs != null) updates['penalty_ms'] = penaltyMs;
    if (updates.isEmpty) return;
    await _db.update('strings', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TimerString>> listStrings({int limit = 200, int offset = 0}) async {
    final rows = await _db.query(
      'strings',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    final results = <TimerString>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final shots = await _readShots(_db, id);
      results.add(TimerString.fromMap(row, shots: shots));
    }
    return results;
  }

  Future<TimerString?> getString(int id) async {
    final rows = await _db.query('strings', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final shots = await _readShots(_db, id);
    return TimerString.fromMap(rows.first, shots: shots);
  }

  Future<int> countStrings() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS c FROM strings');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> deleteString(int id) async {
    await _db.delete('strings', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAll() async {
    await _db.delete('strings');
  }

  Future<void> replaceShots(int stringId, List<Shot> shots) async {
    await _db.transaction((txn) async {
      await txn.delete('shots', where: 'string_id = ?', whereArgs: [stringId]);
      for (final shot in shots) {
        await txn.insert(
          'shots',
          shot.copyWith(stringId: stringId).toMap()..remove('id'),
        );
      }
    });
  }

  Future<void> pruneToCap(int historyCap) =>
      _db.transaction((txn) => _pruneToCap(txn, historyCap));

  Future<List<Shot>> _readShots(DatabaseExecutor exec, int stringId) async {
    final rows = await exec.query(
      'shots',
      where: 'string_id = ?',
      whereArgs: [stringId],
      orderBy: 'idx ASC',
    );
    return rows.map(Shot.fromMap).toList();
  }

  Future<void> _pruneToCap(DatabaseExecutor exec, int historyCap) async {
    if (historyCap <= 0) return;
    final result = await exec.rawQuery('SELECT COUNT(*) AS c FROM strings');
    final count = (result.first['c'] as int?) ?? 0;
    if (count <= historyCap) return;
    final overflow = count - historyCap;
    // Delete the oldest N rows. ORDER BY created_at ASC, id ASC.
    await exec.rawDelete('''
      DELETE FROM strings
      WHERE id IN (
        SELECT id FROM strings
        ORDER BY created_at ASC, id ASC
        LIMIT ?
      )
    ''', [overflow]);
  }

  Future<void> close() => _db.close();
}
