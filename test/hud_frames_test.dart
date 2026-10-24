// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/export_plan.dart';
import 'package:simple_shot_timer/services/video/hud.dart';
import 'package:simple_shot_timer/services/video/hud_frames.dart';
import 'package:simple_shot_timer/services/video/hud_painter.dart';

void main() {
  // START at 10 s; shots 1.0 and 1.5 s after it; a 640x360 clip at 10 fps
  // keeps the image count small.
  final string = HudString(
    TimerString(
      createdAt: DateTime(2026, 10, 23),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [Shot(index: 0, timeMs: 1000), Shot(index: 1, timeMs: 1500)],
    ),
    startMs: 10000,
  );
  const info = ClipInfo(
      hasAudio: true,
      durationMs: 30000,
      width: 640,
      height: 360,
      frameRate: 10);
  final plan = ExportPlan(string, info, fromMs: 0, toMs: 30000);
  const labels = HudLabels(
    total: 'TOTAL',
    first: 'FIRST',
    average: 'AVERAGE',
    fastest: 'FASTEST',
    shots: 'SHOTS',
    penaltyTemplate: 'Penalty: \u0000s',
    locale: 'en',
  );

  testWidgets('draws a still, a frame per frame of the run, and the card fade',
      (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('en');
      final dir = await Directory.systemTemp.createTemp('hud_frames');
      addTearDown(() => dir.delete(recursive: true));
      final progress = <double>[];
      final sequences = await renderHudFrames(
        dir: dir,
        plan: plan,
        string: string,
        options: const HudOptions(),
        labels: labels,
        onProgress: progress.add,
      );
      final [box, card] = sequences;

      // The still, then frames from START (10.0 s) to the first past the
      // last shot's tick (11.62 s), each half a frame (50 ms) early.
      expect(box.timesUs.first, 0);
      expect(box.timesUs[1], (10000 - 7000 - 50) * 1000);
      expect(box.timesUs, hasLength(1 + 18));
      for (var i = 1; i < box.timesUs.length; i++) {
        expect(box.timesUs[i], greaterThan(box.timesUs[i - 1]));
      }
      // Nothing, then the fade from 12.0 s to 12.3 s and one more.
      expect(card.timesUs.first, 0);
      expect(card.timesUs, hasLength(1 + 5));

      for (final s in sequences) {
        final images = Directory(s.dir).listSync().whereType<File>().toList();
        expect(images, hasLength(s.timesUs.length));
        final pixels = zlib.decode(File('${s.dir}/1.z').readAsBytesSync());
        expect(pixels, hasLength(s.width * s.height * 4));
      }
      expect(box.x, greaterThan(0));
      expect(card.x * 640 + card.width / 2, closeTo(320, 1));
      expect(progress.last, 1);
    });
  });

  testWidgets('the whole video also fades the card out, to nothing',
      (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('en');
      final dir = await Directory.systemTemp.createTemp('hud_frames');
      addTearDown(() => dir.delete(recursive: true));
      final [box, card] = await renderHudFrames(
        dir: dir,
        plan: ExportPlan.whole(info),
        string: string,
        options: const HudOptions(),
        labels: labels,
      );

      // Clip time is output time: the still from 0, START at 10 s.
      expect(box.timesUs[1], (10000 - 50) * 1000);
      expect(box.timesUs, hasLength(1 + 18));
      // Nothing, the fade in, then the fade out from 16.0 s to 16.3 s and
      // one more.
      expect(card.timesUs, hasLength(1 + 5 + 5));
      expect(card.timesUs[6], (16000 - 50) * 1000);
      final last = card.timesUs.length - 1;
      final pixels = zlib.decode(File('${card.dir}/$last.z').readAsBytesSync());
      expect(pixels.every((b) => b == 0), isTrue);
      final shown = zlib.decode(File('${card.dir}/5.z').readAsBytesSync());
      expect(shown.any((b) => b != 0), isTrue);
    });
  });
}
