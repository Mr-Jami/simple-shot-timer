// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the video feature keeps its working files: one folder per imported
/// clip under `<app support>/video_work/`. Not the cache folder, which
/// Android empties under storage pressure, even mid-edit.
///
/// No clip outlives its editor: a session deletes its folder when it closes,
/// [sweep] removes leftovers at app start (after a crash or a kill), and
/// "Delete all data and settings" calls [deleteAll]. Both also remove what
/// the photo picker (image_picker) left in the cache: it copies the video
/// to `<cache>/<uuid>/` before handing it over, so a pick given up during
/// that copy, or cut short by a kill, leaves a full copy there. On iOS the
/// pickers copy into the temporary folder instead: image_picker to
/// `image_picker_*` files, the document picker to a `*-Inbox` folder.
class VideoWorkDir {
  VideoWorkDir({
    Future<Directory> Function()? root,
    Future<Directory> Function()? cache,
    Future<Directory?> Function()? temp,
  })  : _root = root ?? _defaultRoot,
        _cache = cache ?? getTemporaryDirectory,
        _temp = temp ?? _defaultTemp;

  final Future<Directory> Function() _root;
  final Future<Directory> Function() _cache;
  final Future<Directory?> Function() _temp;

  /// The folder image_picker copies a picked file into.
  static final _pickerCopy =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/video_work');

  /// The pickers' folder on iOS; elsewhere they use the cache.
  static Future<Directory?> _defaultTemp() async =>
      Platform.isIOS ? Directory.systemTemp : null;

  Future<VideoSession> createSession() async {
    final root = await _root();
    final dir = Directory(
      '${root.path}/${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    return VideoSession(dir);
  }

  /// Removes every session folder and the pickers' copies. Only call it
  /// when no import or editor is open.
  Future<void> sweep() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
    await _deleteIn(
      await _cache(),
      (entity, name) => entity is Directory && _pickerCopy.hasMatch(name),
    );
    await _deleteIn(
      await _temp(),
      (entity, name) =>
          (entity is File && name.startsWith('image_picker_')) ||
          (entity is Directory && name.endsWith('-Inbox')),
    );
  }

  /// Deletes what [matches] in [dir], if there is such a folder.
  static Future<void> _deleteIn(
    Directory? dir,
    bool Function(FileSystemEntity entity, String name) matches,
  ) async {
    if (dir == null || !await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (matches(entity, p.basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
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
      try {
        await source.copy(target);
      } finally {
        // Never leave the picker's copy behind, also when this folder is
        // already gone (the import was cancelled while the picker copied).
        try {
          await source.delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
    return _clipPath = target;
  }

  /// The decoded sound is only needed while it is analysed.
  Future<void> deletePcm() async {
    try {
      await File(pcmPath).delete();
    } on FileSystemException {
      // Already gone.
    }
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
