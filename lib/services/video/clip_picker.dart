// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/cancel_token.dart';
import 'clip_audio_source.dart';
import 'video_work_dir.dart';

enum ClipSource {
  /// The photo picker (no media permission).
  photos,

  /// The system document picker ("or choose from Files").
  files,
}

/// Lets the user choose one video and brings it into a session folder.
abstract interface class ClipPicker {
  /// The chosen video's path inside [session], or null when the user backs
  /// out. [onCopyProgress] gets 0..1 while a Files pick copies the video,
  /// and [cancel] stops that copy (it then throws
  /// [ClipAudioError.cancelled]). Throws a [ClipAudioException] when the
  /// video can't be read.
  Future<String?> pick(
    ClipSource source,
    VideoSession session, {
    void Function(double fraction)? onCopyProgress,
    CancelToken? cancel,
  });
}

/// Photos through image_picker, whose copy lands in the cache (iOS: the
/// temporary folder) and is moved into the session; Files through
/// `cc.jami.simpleshottimer/clip_files` (`ClipFilesChannel.kt`, which copies
/// straight into it; `ClipFilesChannel.swift`, which moves the document
/// picker's copy there).
class PluginClipPicker implements ClipPicker {
  PluginClipPicker({ImagePicker? photos, MethodChannel? files})
      : _photos = photos ?? ImagePicker(),
        _files =
            files ?? const MethodChannel('cc.jami.simpleshottimer/clip_files') {
    _files.setMethodCallHandler((call) async {
      if (call.method != 'copyProgress') return;
      final fraction = ((call.arguments as Map)['fraction'] as num).toDouble();
      _onCopyProgress?.call(fraction);
    });
  }

  final ImagePicker _photos;
  final MethodChannel _files;
  void Function(double)? _onCopyProgress;

  /// Names each Files pick, so a late cancel of an earlier one (its import
  /// is disposed a frame after "Choose another" starts the next) can't stop
  /// this copy.
  static var _nextPickId = 1;

  @override
  Future<String?> pick(
    ClipSource source,
    VideoSession session, {
    void Function(double fraction)? onCopyProgress,
    CancelToken? cancel,
  }) async {
    try {
      switch (source) {
        case ClipSource.photos:
          final file = await _photos.pickVideo(source: ImageSource.gallery);
          return file == null ? null : await session.adopt(file.path);
        case ClipSource.files:
          _onCopyProgress = onCopyProgress;
          final pickId = _nextPickId++;
          unawaited(cancel?.whenCancelled.then((_) async {
            try {
              await _files.invokeMethod<void>('cancel', {'pickId': pickId});
            } on Exception {
              // The pick reports its own end.
            }
          }));
          final path = await _files.invokeMethod<String>(
            'pickVideo',
            {'targetDir': session.dir.path, 'pickId': pickId},
          );
          return path == null ? null : await session.adopt(path);
      }
    } on PlatformException catch (e) {
      throw ClipAudioException(
        switch (e.code) {
          'copy_failed' => ClipAudioError.unreadableFile,
          'no_space' => ClipAudioError.noSpace,
          'cancelled' => ClipAudioError.cancelled,
          _ => ClipAudioError.unavailable,
        },
        e.message,
      );
    } on MissingPluginException {
      throw const ClipAudioException(ClipAudioError.unavailable);
    } finally {
      _onCopyProgress = null;
    }
  }
}
