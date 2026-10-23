// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/clip_picker.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/utils/cancel_token.dart';

class _FakePhotos extends ImagePicker {
  _FakePhotos(this.path);

  final String? path;

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async =>
      path == null ? null : XFile(path!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cc.jami.simpleshottimer/clip_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late VideoSession session;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('clip_picker_test');
    session = await VideoWorkDir(
      root: () async => Directory('${temp.path}/video_work'),
    ).createSession();
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  Future<void> fromPlatform(String method, Object? arguments) =>
      messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        null,
      );

  test('Files copies into the session and reports progress', () async {
    final picker = PluginClipPicker(files: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickVideo');
      final dir = (call.arguments as Map)['targetDir'] as String;
      await fromPlatform('copyProgress', {'fraction': 0.5});
      final file = File('$dir/range.mp4')..writeAsStringSync('video');
      return file.path;
    });
    final seen = <double>[];
    final path =
        await picker.pick(ClipSource.files, session, onCopyProgress: seen.add);
    expect(path, '${session.dir.path}/range.mp4');
    expect(session.clipPath, path);
    expect(seen, [0.5]);
  });

  test('backing out of a picker gives null', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
        await PluginClipPicker(files: channel).pick(ClipSource.files, session),
        isNull);
    expect(
        await PluginClipPicker(photos: _FakePhotos(null), files: channel)
            .pick(ClipSource.photos, session),
        isNull);
  });

  test('a failed copy is an unreadable file', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'copy_failed', message: 'gone');
    });
    await expectLater(
      PluginClipPicker(files: channel).pick(ClipSource.files, session),
      throwsA(isA<ClipAudioException>()
          .having((e) => e.error, 'error', ClipAudioError.unreadableFile)),
    );
  });

  test('a full storage is its own error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'no_space', message: 'ENOSPC');
    });
    await expectLater(
      PluginClipPicker(files: channel).pick(ClipSource.files, session),
      throwsA(isA<ClipAudioException>()
          .having((e) => e.error, 'error', ClipAudioError.noSpace)),
    );
  });

  test('cancel stops a Files copy, naming its pick', () async {
    final copying = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'cancel') {
        copying.completeError(PlatformException(code: 'cancelled'));
        return null;
      }
      return copying.future;
    });
    final token = CancelToken();
    final picking = PluginClipPicker(files: channel)
        .pick(ClipSource.files, session, cancel: token);
    await pumpEventQueue();
    token.cancel();
    await expectLater(
      picking,
      throwsA(isA<ClipAudioException>()
          .having((e) => e.error, 'error', ClipAudioError.cancelled)),
    );
    expect(calls.map((c) => c.method), ['pickVideo', 'cancel']);
    final pickId = (calls.first.arguments as Map)['pickId'];
    expect(pickId, isA<int>());
    expect((calls.last.arguments as Map)['pickId'], pickId);
  });

  test('a late cancel of an earlier pick names that pick, not the next',
      () async {
    final picks = <int>[];
    final cancels = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final id = (call.arguments as Map)['pickId'] as int;
      (call.method == 'cancel' ? cancels : picks).add(id);
      return call.method == 'cancel' ? null : '${session.dir.path}/clip.mp4';
    });
    final picker = PluginClipPicker(files: channel);
    final first = CancelToken();
    await picker.pick(ClipSource.files, session, cancel: first);
    await picker.pick(ClipSource.files, session, cancel: CancelToken());
    // "Choose another": the first import is disposed after the next began.
    first.cancel();
    await pumpEventQueue();
    expect(picks, hasLength(2));
    expect(cancels, [picks.first]);
  });

  test('Photos moves the picker\'s cache copy into the session', () async {
    final cached = File('${temp.path}/cache/x/clip.mp4')
      ..createSync(recursive: true)
      ..writeAsStringSync('video');
    final path = await PluginClipPicker(
      photos: _FakePhotos(cached.path),
      files: channel,
    ).pick(ClipSource.photos, session);
    expect(path, '${session.dir.path}/clip.mp4');
    expect(cached.existsSync(), isFalse);
  });
}
