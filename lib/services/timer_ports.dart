import 'dart:async';

import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/shot.dart';
import '../models/timer_string.dart';
import 'background_service.dart';

// The four things a timer run touches outside its own state. `TimerNotifier`
// depends on these interfaces, not on the plugin-backed classes, so the run
// logic can be driven in a plain Dart test with fakes.

/// Microphone side: permission, the detection and beep-onset streams and the
/// live level. Implemented by `ShotDetector`.
abstract interface class ShotSource {
  Future<bool> hasPermission();
  Stream<int> get events;
  Stream<int> get beepOnsetEvents;
  double get lastPeak;
  Future<void> start({
    required Stopwatch clock,
    required double threshold,
    required int echoFilterMs,
    int blankingMs = 0,
    bool bandFilterEnabled = false,
    int bandLowHz = 0,
    int bandHighHz = 0,
  });
  Future<void> stop();
  void armBeepDetection();
  void cancelBeepDetection();
}

/// Beep playback. Implemented by `AudioService`.
abstract interface class BeepPlayer {
  Future<void> playStartBeep({required double volume});
  Future<void> playParBeep({required double volume});
}

/// Persistence of strings and their shots. Implemented by `DatabaseService`.
abstract interface class StringStore {
  Future<TimerString> insertString(TimerString s, {required int historyCap});
  Future<void> replaceShots(int stringId, List<Shot> shots);
  Future<void> updateStringMeta(
    int id, {
    String? label,
    String? notes,
    int? penaltyMs,
  });
}

/// Device side effects of a run: screen wake lock, foreground service,
/// haptics.
abstract interface class RunEnvironment {
  Future<void> setKeepAwake(bool on);
  Future<void> setForeground(bool on);
  Future<void> vibrate();
}

/// The real thing, backed by wakelock_plus, flutter_foreground_task and
/// vibration.
class PluginRunEnvironment implements RunEnvironment {
  const PluginRunEnvironment();

  @override
  Future<void> setKeepAwake(bool on) async {
    if (on) {
      await WakelockPlus.enable();
    } else if (await WakelockPlus.enabled) {
      await WakelockPlus.disable();
    }
  }

  /// Promotes to a foreground service so Android won't suspend the mic
  /// stream or kill the beep timers when the user locks the screen or
  /// switches apps. On iOS this is a no-op (the audio background mode in
  /// Info.plist handles it via the active AVAudioSession).
  @override
  Future<void> setForeground(bool on) =>
      on ? BackgroundService.start() : BackgroundService.stop();

  @override
  Future<void> vibrate() async {
    if (await Vibration.hasVibrator()) {
      unawaited(Vibration.vibrate(duration: 100));
    }
  }
}
