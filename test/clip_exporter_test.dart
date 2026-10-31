// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_exporter.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cc.jami.simpleshottimer/clip_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final exporter = ChannelClipExporter();
  final calls = <MethodCall>[];

  void installHandler(Object? Function(MethodCall call) onCall) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return onCall(call);
    });
  }

  Future<void> fromPlatform(String method, Object? arguments) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const request = ExportRequest(
    input: '/work/clip.mp4',
    output: '/work/out.mp4',
    startMs: 7000,
    endMs: 16000,
    shortSide: 1080,
    maxFps: 60,
    bitrate: 12000000,
    colorFix: true,
    overlays: [
      OverlaySequence(
          dir: '/work/overlay/box',
          width: 486,
          height: 572,
          timesUs: [0, 2950000],
          x: 0.04,
          y: 0.05),
    ],
  );

  test('export sends the whole request and passes on its progress', () async {
    final done = Completer<Object?>();
    installHandler((call) => done.future);
    final seen = <double>[];
    final exporting = exporter.export(request, onProgress: seen.add);
    await pumpEventQueue();
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(calls.single.method, 'export');
    expect([args['input'], args['output'], args['startMs'], args['endMs']],
        ['/work/clip.mp4', '/work/out.mp4', 7000, 16000]);
    expect([args['shortSide'], args['maxFps'], args['colorFix']],
        [1080, 60.0, true]);
    final overlay = (args['overlays'] as List).single as Map;
    expect(overlay['timesUs'], [0, 2950000]);
    expect([overlay['width'], overlay['x']], [486, 0.04]);

    await fromPlatform('progress', {'jobId': args['jobId'], 'fraction': 0.4});
    await fromPlatform(
        'progress', {'jobId': (args['jobId'] as int) + 1, 'fraction': 0.9});
    done.complete(null);
    await exporting;
    expect(seen, [0.4]);
  });

  test('cancel names the job; a cancelled export says so', () async {
    final done = Completer<Object?>();
    installHandler((call) {
      if (call.method == 'cancel') {
        done.completeError(PlatformException(code: 'cancelled'));
        return null;
      }
      return done.future;
    });
    final token = CancelToken();
    final exporting = exporter.export(request, cancel: token);
    await pumpEventQueue();
    token.cancel();
    await expectLater(
      exporting,
      throwsA(isA<ExportException>()
          .having((e) => e.error, 'error', ExportError.cancelled)),
    );
    expect(calls.map((c) => c.method), ['export', 'cancel']);
    expect((calls[1].arguments as Map)['jobId'],
        (calls[0].arguments as Map)['jobId']);
  });

  test('failures and a missing exporter have their own errors', () async {
    installHandler((_) =>
        throw PlatformException(code: 'export_failed', message: 'codec'));
    await expectLater(
      exporter.export(request),
      throwsA(isA<ExportException>()
          .having((e) => e.error, 'error', ExportError.failed)
          .having((e) => e.message, 'message', 'codec')),
    );
    installHandler(
        (_) => throw PlatformException(code: 'no_space', message: 'ENOSPC'));
    await expectLater(
      exporter.export(request),
      throwsA(isA<ExportException>()
          .having((e) => e.error, 'error', ExportError.noSpace)),
    );
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      exporter.export(request),
      throwsA(isA<ExportException>()
          .having((e) => e.error, 'error', ExportError.unavailable)),
    );
  });

  test('only a BT.601 encoder needs the colour fix', () async {
    installHandler((_) => {'needsFix': true});
    expect(await exporter.encoderNeedsColorFix(), isTrue);
    installHandler((_) => {'needsFix': false});
    expect(await exporter.encoderNeedsColorFix(), isFalse);
  });
}
