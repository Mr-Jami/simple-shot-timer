// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';

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
          'colorTransfer': 'hlg',
          'frameRate': 29.97,
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
    final audio =
        await source.decode('/clips/a.mp4', outputPath: '/tmp/a.pcm');
    expect(calls.single.method, 'decode');
    expect(calls.single.arguments,
        {'path': '/clips/a.mp4', 'outputPath': '/tmp/a.pcm'});
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
      'decode_failed': ClipAudioError.decodeFailed,
      'something_new': ClipAudioError.decodeFailed,
    };
    cases.forEach((code, error) {
      test(code, () async {
        installHandler((_) =>
            throw PlatformException(code: code, message: 'audio/ac3'));
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
}
