// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/models/enums.dart';
import 'package:simple_shot_timer/models/shot.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/video_export_provider.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/services/timer_ports.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_exporter.dart';
import 'package:simple_shot_timer/services/video/export_plan.dart';
import 'package:simple_shot_timer/services/video/hud.dart';
import 'package:simple_shot_timer/services/video/video_gallery.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';
import 'package:simple_shot_timer/widgets/video/hud_painter.dart';

import 'clip_fixtures.dart';

class _FakeExporter implements ClipExporter {
  ExportRequest? request;
  CancelToken? cancel;
  var colorChecks = 0;
  bool needsFix = true;
  ExportException? error;

  /// Completes the export; null finishes at once.
  Completer<void>? running;

  @override
  Future<ExportedClip> export(
    ExportRequest request, {
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    this.request = request;
    this.cancel = cancel;
    onProgress?.call(0.5);
    if (running != null) {
      await Future.any([running!.future, cancel!.whenCancelled]);
    }
    if (cancel?.isCancelled ?? false) {
      throw const ExportException(ExportError.cancelled);
    }
    if (error != null) throw error!;
    await File(request.output).writeAsString('mp4');
    return ExportedClip(
        path: request.output, fileSizeBytes: 3, width: 1920, height: 1080);
  }

  @override
  Future<bool> encoderNeedsColorFix() async {
    colorChecks++;
    return needsFix;
  }
}

class _FakeGallery implements VideoGallery {
  bool allowed = true;
  final saved = <String>[];
  final shared = <String>[];

  @override
  Future<bool> save(String path) async {
    if (allowed) saved.add(path);
    return allowed;
  }

  @override
  Future<void> share(String path) async => shared.add(path);
}

class _FakeEnvironment implements RunEnvironment {
  final awake = <bool>[];

  @override
  Future<void> setKeepAwake(bool on) async => awake.add(on);
  @override
  Future<void> setForeground(bool on) async {}
  @override
  Future<void> vibrate() async {}
}

void main() {
  late Directory temp;
  late VideoSession session;
  late _FakeExporter exporter;
  late _FakeGallery gallery;
  late _FakeEnvironment env;
  late ExportPlan? renderedPlan;

  final analysis = analyzePcm(
    syntheticClip(extra: (x) => addBeep(x, 1.0, 300)),
    clipSampleRate,
  );
  final clip = AnalyzedClip(
    info: const ClipInfo(
      hasAudio: true,
      durationMs: 30000,
      videoMime: 'video/hevc',
      width: 3840,
      height: 2160,
      frameRate: 30,
    ),
    analysis: analysis,
    audioOriginMs: 0,
  );
  final string = HudString(
    TimerString(
      createdAt: DateTime(2026, 10, 23),
      drillMode: DrillMode.standard,
      delayMode: DelayMode.instant,
      delayUsedMs: 0,
      pars: const [],
      shots: [Shot(index: 0, timeMs: 1500), Shot(index: 1, timeMs: 2000)],
      source: StringSource.video,
    ),
    startMs: 10000,
  );
  const labels = HudLabels(
    total: 'TOTAL',
    first: 'FIRST',
    average: 'AVERAGE',
    fastest: 'FASTEST',
    shots: 'SHOTS',
    penaltyTemplate: 'Penalty: \u0000s',
    locale: 'en',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('export_test');
    session = VideoSession(temp);
    final picked = File('${temp.path}/clip.mp4')..writeAsStringSync('clip');
    await session.adopt(picked.path);
    exporter = _FakeExporter();
    gallery = _FakeGallery();
    env = _FakeEnvironment();
    renderedPlan = null;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clipExporterProvider.overrideWithValue(exporter),
      videoGalleryProvider.overrideWithValue(gallery),
      runEnvironmentProvider.overrideWithValue(env),
      hudFrameRendererProvider.overrideWithValue((
          {required Directory dir,
          required ExportPlan plan,
          required HudString string,
          required HudOptions options,
          required HudLabels labels,
          ui.Image? logo,
          void Function(double fraction)? onProgress,
          CancelToken? cancel}) async {
        renderedPlan = plan;
        await Directory('${dir.path}/box').create(recursive: true);
        onProgress?.call(1);
        return [
          OverlaySequence(
              dir: '${dir.path}/box',
              width: 10,
              height: 10,
              timesUs: const [0],
              x: 0,
              y: 0),
        ];
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// The export [id], kept alive as the dialog keeps it.
  VideoExportController export(ProviderContainer c, int id) {
    c.listen(videoExportProvider(id), (_, __) {});
    return c.read(videoExportProvider(id).notifier);
  }

  ExportJob job(ExportTarget target) => ExportJob(
        clip: clip,
        session: session,
        string: string,
        options: const HudOptions(),
        labels: labels,
        target: target,
      );

  test('exports the string with margins, scaled, then saves it', () async {
    final c = await container();
    final seen = <ExportState>[];
    c.listen(videoExportProvider(1), (_, s) => seen.add(s),
        fireImmediately: true);
    await c
        .read(videoExportProvider(1).notifier)
        .start(job(ExportTarget.photos));

    final r = exporter.request!;
    expect((r.startMs, r.endMs), (7000, 16000));
    expect(r.shortSide, 1080);
    expect(r.colorFix, isTrue);
    expect(r.input, session.clipPath);
    expect(r.output, endsWith('SimpleShotTimer_2026-10-23_2.00s.mp4'));
    expect(renderedPlan!.frame.shortestSide, 1080);
    expect(
        seen.whereType<ExportRunning>().map((s) => (s.progress * 100).round()),
        containsAllInOrder([0, 20, 60]));
    final done = seen.last as ExportDone;
    expect(done.saved, isTrue);
    expect(gallery.saved, [r.output]);
    expect(env.awake, [true, false]);
    // The overlay images are gone; the video stays for Share.
    expect(Directory('${temp.path}/overlay').existsSync(), isFalse);
    expect(File(r.output).existsSync(), isTrue);
  });

  test('asks the encoder about its colours once, then remembers', () async {
    final c = await container();
    exporter.needsFix = false;
    await export(c, 1).start(job(ExportTarget.share));
    await export(c, 2).start(job(ExportTarget.share));
    expect(exporter.colorChecks, 1);
    expect(exporter.request!.colorFix, isFalse);
    expect(gallery.shared, hasLength(2));
  });

  test('Cancel stops the export and lets the screen sleep', () async {
    final c = await container();
    exporter.running = Completer();
    final controller = export(c, 1);
    final running = controller.start(job(ExportTarget.photos));
    await pumpEventQueue();
    controller.cancel();
    await running;
    expect(exporter.cancel!.isCancelled, isTrue);
    expect(c.read(videoExportProvider(1)), isA<ExportCancelled>());
    expect(gallery.saved, isEmpty);
    expect(env.awake, [true, false]);
  });

  test('a refused save still leaves the video to share', () async {
    final c = await container();
    gallery.allowed = false;
    final controller = export(c, 1);
    await controller.start(job(ExportTarget.photos));
    expect(c.read(videoExportProvider(1)), isA<ExportNoAccess>());
    await controller.deliver(ExportTarget.share);
    expect(gallery.shared, [exporter.request!.output]);
  });

  test('a failed export says so and cleans up', () async {
    final c = await container();
    exporter.error = const ExportException(ExportError.failed, 'codec');
    await export(c, 1).start(job(ExportTarget.photos));
    expect(c.read(videoExportProvider(1)), isA<ExportFailed>());
    expect(env.awake, [true, false]);
    expect(Directory('${temp.path}/overlay').existsSync(), isFalse);
  });

  group('the plan', () {
    test('keeps 4K under 1080, 60 fps sources at 60 and names the file', () {
      final plan = ExportPlan(string, clip.info, fromMs: 0, toMs: 30000);
      expect(plan.frame, const ui.Size(1920, 1080));
      expect(plan.maxFps, isNull);
      final fast = ExportPlan(
        string,
        const ClipInfo(
            hasAudio: true,
            durationMs: 30000,
            width: 1080,
            height: 1920,
            frameRate: 120),
        fromMs: 0,
        toMs: 30000,
      );
      expect(fast.shortSide, isNull);
      expect((fast.fps, fast.maxFps), (60.0, 60.0));
      expect(fast.bitrate, 16000000);
      expect(ExportPlan.fileName(DateTime(2026, 1, 2), 21470),
          'SimpleShotTimer_2026-01-02_21.47s.mp4');
    });

    test('stays inside the analysed part', () {
      final plan = ExportPlan(string, clip.info, fromMs: 9000, toMs: 13000);
      expect((plan.startMs, plan.endMs), (9000, 13000));
    });
  });
}
