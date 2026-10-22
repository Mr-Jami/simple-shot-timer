// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The only place the video feature keeps files: one folder per imported
/// clip under `<app support>/video_work/`. Not the cache folder, which
/// Android empties under storage pressure, even mid-edit.
///
/// Nothing in it outlives the editor: a session deletes its folder when it
/// closes, [sweep] removes leftovers at app start (after a crash or a kill),
/// and "Delete all data and settings" calls [deleteAll].
class VideoWorkDir {
  VideoWorkDir({Future<Directory> Function()? root})
      : _root = root ?? _defaultRoot;

  final Future<Directory> Function() _root;

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/video_work');

  Future<VideoSession> createSession() async {
    final root = await _root();
    final dir = Directory(
      '${root.path}/${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    return VideoSession(dir);
  }

  /// Removes every session folder. Only call it when no editor is open.
  Future<void> sweep() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<void> deleteAll() => sweep();
}

/// One imported clip's folder: the clip, moved out of the picker's cache
/// copy, and its decoded sound while it is analysed.
class VideoSession {
  VideoSession(this.dir);

  final Directory dir;

  String? _clipPath;
  var _disposed = false;

  String get clipPath => _clipPath!;
  String get pcmPath => '${dir.path}/audio.pcm';

  /// Moves the picker's copy at [pickedPath] into this folder (a rename on
  /// the same disk, else a copy and delete) and returns its new path. A file
  /// already in the folder just becomes the clip.
  Future<String> adopt(String pickedPath) async {
    final source = File(pickedPath);
    final name = pickedPath.split(RegExp(r'[/\\]')).last;
    final target = '${dir.path}/$name';
    if (source.absolute.path == File(target).absolute.path) {
      return _clipPath = target;
    }
    try {
      await source.rename(target);
    } on FileSystemException {
      await source.copy(target);
      await source.delete();
    }
    return _clipPath = target;
  }

  /// Deletes the folder. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // The next app start sweeps it.
    }
  }
}
