// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cc.jami.simpleshottimer/clip_audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final source = ChannelClipAudioSource();
  final calls = <MethodCall>[];

  void installHandler(Object? Function(MethodCall call) onCall) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return onCall(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('probe passes the path and reads every field', () async {
    installHandler((_) => {
          'hasAudio': true,
          'durationMs': 20067,
          'audioMime': 'audio/mp4a-latm',
          'videoMime': 'video/hevc',
          'rotation': 90,
          'width': 1080,
          'height': 1920,
          'colorTransfer': 'hlg',
          'frameRate': 29.97,
          'captureFrameRate': 240.0,
          'creationTimeMs': 1790000000000,
        });
    final info = await source.probe('/clips/a.mp4');
    expect(calls.single.method, 'probe');
    expect(calls.single.arguments, {'path': '/clips/a.mp4'});
    expect(info.hasAudio, isTrue);
    expect(info.durationMs, 20067);
    expect(info.audioMime, 'audio/mp4a-latm');
    expect(info.videoMime, 'video/hevc');
    expect(info.rotationDegrees, 90);
    expect(info.isHdr, isTrue);
    expect(info.frameRate, closeTo(29.97, 1e-9));
    expect((info.width, info.height), (1080, 1920));
    expect(info.captureFrameRate, 240);
    expect(info.creationTime,
        DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true));
  });

  test('probe tolerates a platform that knows little', () async {
    installHandler((_) => {'hasAudio': false, 'durationMs': 5000});
    final info = await source.probe('/clips/b.mp4');
    expect(info.hasAudio, isFalse);
    expect(info.rotationDegrees, 0);
    expect(info.isHdr, isFalse);
    expect(info.creationTime, isNull);
  });

  test('decode passes both paths and reads the PCM description', () async {
    installHandler((_) => {
          'sampleRate': 48000,
          'channelCount': 2,
          'sampleCount': 963200,
          'firstSampleTimeUs': 0,
        });
    final audio = await source.decode('/clips/a.mp4', outputPath: '/tmp/a.pcm');
    expect(calls.single.method, 'decode');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['path'], '/clips/a.mp4');
    expect(args['outputPath'], '/tmp/a.pcm');
    expect(args['jobId'], isA<int>());
    expect(audio.pcmPath, '/tmp/a.pcm');
    expect(audio.sampleRate, 48000);
    expect(audio.channelCount, 2);
    expect(audio.durationSeconds, closeTo(20.067, 1e-3));
  });

  group('turns platform errors into typed ones', () {
    const cases = {
      'no_audio_track': ClipAudioError.noAudioTrack,
      'unsupported_codec': ClipAudioError.unsupportedCodec,
      'unreadable_file': ClipAudioError.unreadableFile,
      'unsupported_file': ClipAudioError.unsupportedFile,
      'no_space': ClipAudioError.noSpace,
      'decode_failed': ClipAudioError.decodeFailed,
      'cancelled': ClipAudioError.cancelled,
      'something_new': ClipAudioError.decodeFailed,
    };
    cases.forEach((code, error) {
      test(code, () async {
        installHandler(
            (_) => throw PlatformException(code: code, message: 'audio/ac3'));
        await expectLater(
          source.decode('/clips/a.mp4', outputPath: '/tmp/a.pcm'),
          throwsA(isA<ClipAudioException>()
              .having((e) => e.error, 'error', error)
              .having((e) => e.message, 'message', 'audio/ac3')),
        );
      });
    });

    test('a platform without the decoder', () async {
      // No handler installed: invokeMethod throws MissingPluginException.
      await expectLater(
        source.probe('/clips/a.mp4'),
        throwsA(isA<ClipAudioException>()
            .having((e) => e.error, 'error', ClipAudioError.unavailable)),
      );
    });
  });

  group('a long decode', () {
    Future<void> fromPlatform(String method, Object? arguments) =>
        messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, arguments)),
          null,
        );
    const decoded = {
      'sampleRate': 48000,
      'channelCount': 1,
      'sampleCount': 48000,
    };

    test('reports progress to its own caller only', () async {
      final done = Completer<Object?>();
      installHandler((call) => done.future);
      final seen = <double>[];
      final decoding = source.decode('/clips/a.mp4',
          outputPath: '/tmp/a.pcm', onProgress: seen.add);
      await pumpEventQueue();
      final jobId = (calls.single.arguments as Map)['jobId'] as int;
      await fromPlatform('progress', {'jobId': jobId + 1, 'fraction': 0.9});
      await fromPlatform('progress', {'jobId': jobId, 'fraction': 0.25});
      await fromPlatform('progress', {'jobId': jobId, 'fraction': 0.5});
      done.complete(decoded);
      await decoding;
      expect(seen, [0.25, 0.5]);
    });

    test('cancel tells the platform which job to stop', () async {
      final done = Completer<Object?>();
      installHandler((call) {
        if (call.method == 'cancel') {
          done.completeError(PlatformException(code: 'cancelled'));
          return null;
        }
        return done.future;
      });
      final token = CancelToken();
      final decoding = source.decode('/clips/a.mp4',
          outputPath: '/tmp/a.pcm', cancel: token);
      await pumpEventQueue();
      token.cancel();
      await expectLater(
        decoding,
        throwsA(isA<ClipAudioException>()
            .having((e) => e.error, 'error', ClipAudioError.cancelled)),
      );
      expect(calls.map((c) => c.method), ['decode', 'cancel']);
      expect((calls[1].arguments as Map)['jobId'],
          (calls[0].arguments as Map)['jobId']);
    });

    test('a window goes to the platform; its sound keeps clip time', () async {
      installHandler((_) => {...decoded, 'firstSampleTimeUs': 60001000});
      final audio = await source.decode('/clips/a.mp4',
          outputPath: '/tmp/a.pcm', startMs: 60000, endMs: 240000);
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect((args['startMs'], args['endMs']), (60000, 240000));
      expect(audio.firstSampleTimeUs, 60001000);
    });

    test('the loudness scan hands over its batches in order', () async {
      final done = Completer<Object?>();
      installHandler((call) => done.future);
      final seen = <(int, List<double>)>[];
      final scanning = source.scanLoudness('/clips/long.mp4',
          onValues: (from, values) => seen.add((from, values)));
      await pumpEventQueue();
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(calls.single.method, 'loudness');
      expect(args['bucketMs'], 250);
      final jobId = args['jobId'] as int;
      await fromPlatform('loudness', {
        'jobId': jobId,
        'from': 0,
        'values': [0.1, 0.5],
      });
      await fromPlatform('progress', {'jobId': jobId, 'fraction': 0.5});
      await fromPlatform('loudness', {
        'jobId': jobId,
        'from': 2,
        'values': [0.25],
      });
      done.complete({'buckets': 3, 'sampleRate': 48000});
      expect(await scanning, 3);
      expect([
        for (final (from, values) in seen) [from, ...values]
      ], [
        [0, 0.1, 0.5],
        [2, 0.25],
      ]);
    });

    test('filmstrip frames arrive one by one; cancel stops them', () async {
      final done = Completer<Object?>();
      installHandler((call) {
        if (call.method == 'cancel') {
          done.completeError(PlatformException(code: 'cancelled'));
          return null;
        }
        return done.future;
      });
      final frames = <int, Uint8List>{};
      final token = CancelToken();
      final loading = source.thumbnails('/clips/long.mp4',
          timesMs: [30000, 90000],
          width: 120,
          onFrame: (i, jpeg) => frames[i] = jpeg,
          cancel: token);
      await pumpEventQueue();
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['timesMs'], [30000, 90000]);
      expect(args['width'], 120);
      await fromPlatform('thumbnail', {
        'jobId': args['jobId'],
        'index': 1,
        'bytes': Uint8List.fromList([0xFF, 0xD8]),
      });
      token.cancel();
      await expectLater(
        loading,
        throwsA(isA<ClipAudioException>()
            .having((e) => e.error, 'error', ClipAudioError.cancelled)),
      );
      expect(frames.keys, [1]);
      expect(frames[1], [0xFF, 0xD8]);
    });

    test('an already cancelled token never starts it', () async {
      installHandler((_) => decoded);
      await expectLater(
        source.decode('/clips/a.mp4',
            outputPath: '/tmp/a.pcm', cancel: CancelToken()..cancel()),
        throwsA(isA<ClipAudioException>()
            .having((e) => e.error, 'error', ClipAudioError.cancelled)),
      );
      expect(calls, isEmpty);
    });
  });
}
