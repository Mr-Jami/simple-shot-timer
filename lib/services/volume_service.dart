// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/services.dart';

/// Asks the platform whether the media stream the beep plays on can be
/// heard, and shows the system volume panel. Handled in
/// `android/.../MainActivity.kt` and `ios/Runner/AppDelegate.swift`.
///
/// Every failure degrades to "unknown" (null) so a missing channel can never
/// block a string from starting.
class VolumeService {
  VolumeService({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('cc.jami.simpleshottimer/volume');

  final MethodChannel _channel;

  /// True if the media stream is unmuted and above zero, false if the beep
  /// would be silent, null when the platform cannot say.
  Future<bool?> isMediaAudible() async {
    try {
      return await _channel.invokeMethod<bool>('isMediaAudible');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens the system volume control so the user can fix it in place. A
  /// no-op where the platform offers no such panel (iOS).
  Future<void> showVolumePanel() async {
    try {
      await _channel.invokeMethod<void>('showVolumePanel');
    } on PlatformException {
      // Nothing to recover; the notice stays on screen.
    } on MissingPluginException {
      // Same.
    }
  }
}
