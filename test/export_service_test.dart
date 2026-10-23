// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:simple_shot_timer/services/export_service.dart';

/// Exports hold labels and notes, so "Delete all data and settings" has to
/// remove them, and only them, from temporary storage.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('sst_export_'));
  tearDown(() => temp.deleteSync(recursive: true));

  File touch(String relative) =>
      File(p.join(temp.path, relative))..createSync(recursive: true);

  test('deleteExports removes exports, including share_plus copies', () async {
    final exports = [
      touch('string_12_1760000000000.csv'),
      touch('string_draft_1760000000000.csv'),
      touch('simple_shot_timer_export_1760000000000.csv'),
      touch(p.join('share_plus', 'simple_shot_timer_export_1760000000000.csv')),
      touch(p.join('share_plus', 'SimpleShotTimer_2026-10-23_21.47s.mp4')),
    ];
    final others = [
      touch('notes.csv'),
      touch('string_12_1760000000000.txt'),
      touch('other_string_12_1760000000000.csv'),
      touch(p.join('share_plus', 'photo.jpg')),
      touch(p.join('nested', 'string_12_1760000000000.csv')),
    ];

    await ExportService().deleteExports(tempDir: temp);

    for (final f in exports) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
    for (final f in others) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  });

  test('deleteVideoShares removes only shared videos', () async {
    final video =
        touch(p.join('share_plus', 'SimpleShotTimer_2026-10-23_21.47s.mp4'));
    final csv = touch(p.join('share_plus', 'string_12_1760000000000.csv'));
    final other = touch(p.join('share_plus', 'holiday.mp4'));

    await ExportService().deleteVideoShares(tempDir: temp);

    expect(video.existsSync(), isFalse);
    expect(csv.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('deleteExports copes with an empty or missing directory', () async {
    await ExportService().deleteExports(tempDir: temp);
    await ExportService()
        .deleteExports(tempDir: Directory(p.join(temp.path, 'missing')));
  });
}
