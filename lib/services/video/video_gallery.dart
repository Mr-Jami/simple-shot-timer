// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Where an exported video goes: the phone's videos, or the share sheet.
abstract interface class VideoGallery {
  /// Saves [path] to the phone's videos (Movies on Android, Photos on iOS).
  /// False when the user doesn't allow it.
  Future<bool> save(String path);

  Future<void> share(String path);
}

/// gal and share_plus.
class PluginVideoGallery implements VideoGallery {
  const PluginVideoGallery();

  @override
  Future<bool> save(String path) async {
    // Only old Androids (10 and below) and iOS ask; newer Androids allow it.
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) return false;
    try {
      await Gal.putVideo(path);
      return true;
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) return false;
      rethrow;
    }
  }

  @override
  Future<void> share(String path) =>
      Share.shareXFiles([XFile(path, mimeType: 'video/mp4')]);
}
