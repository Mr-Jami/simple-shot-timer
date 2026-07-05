import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/shot_detector.dart';

/// Overridden in `main()` after `SharedPreferences.getInstance()` resolves.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

/// Overridden in `main()` after the SQLite database is opened.
final databaseProvider = Provider<DatabaseService>((ref) {
  throw UnimplementedError('DatabaseService must be overridden in main()');
});

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService(ref.watch(sharedPreferencesProvider)),
);

/// Overridden in `main()` with an eagerly-constructed instance. Eager so the
/// constructor's audioplayers AudioContext (an AVAudioSession `setCategory`
/// on iOS) is applied at startup — were it lazily created on the first beep,
/// it would reset the measurement-mode session mid-recording (see
/// `IosAudioSession`).
final audioServiceProvider = Provider<AudioService>((ref) {
  throw UnimplementedError('AudioService must be overridden in main()');
});

final shotDetectorProvider = Provider<ShotDetector>((ref) {
  final detector = ShotDetector();
  ref.onDispose(detector.dispose);
  return detector;
});
