import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Switches the shared iOS `AVAudioSession` between `.measurement` and
/// `.default` modes via a MethodChannel handled in
/// `ios/Runner/AppDelegate.swift`.
///
/// Measurement mode disables Apple's built-in voice DSP (AGC, noise
/// suppression) — the iOS analogue of Android's
/// `AudioSource.unprocessed`. Without it the impulsive transient of a
/// gunshot gets pulled down toward an "average" loudness and either misses
/// the detection threshold or is heavily truncated.
///
/// Both methods are no-ops on non-iOS platforms. Failures are swallowed and
/// surfaced via [lastError] so a session hiccup degrades detection quality
/// instead of blocking the timer.
class IosAudioSession {
  IosAudioSession._();

  static const MethodChannel _channel =
      MethodChannel('cc.jami.simpleshottimer/audio_session');

  /// Most recent session-switch failure, or null if the last call succeeded.
  /// Mirrors the `ShotDetector.lastError` diagnostics pattern.
  static String? lastError;

  /// Call before starting a mic stream so the OS delivers raw samples.
  static Future<void> useMeasurementMode() => _invoke('useMeasurementMode');

  /// Call after the mic stream stops so normal playback processing resumes.
  static Future<void> useDefaultMode() => _invoke('useDefaultMode');

  static Future<void> _invoke(String method) async {
    // defaultTargetPlatform rather than Platform.isIOS so tests can exercise
    // this path with debugDefaultTargetPlatformOverride.
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>(method);
      lastError = null;
    } on PlatformException catch (e) {
      lastError = '$method: ${e.message}';
    } on MissingPluginException {
      lastError = '$method: channel not registered';
    }
  }
}
