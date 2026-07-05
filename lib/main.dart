import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/providers.dart';
import 'services/audio_service.dart';
import 'services/background_service.dart';
import 'services/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the foreground notification channel early so the first start of
  // a string doesn't pay the channel-creation latency.
  BackgroundService.init();
  final prefs = await SharedPreferences.getInstance();
  final db = await DatabaseService.open();
  // Eagerly constructed — see audioServiceProvider for why.
  final audio = AudioService();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        audioServiceProvider.overrideWithValue(audio),
      ],
      child: const SimpleShotTimerApp(),
    ),
  );
}
