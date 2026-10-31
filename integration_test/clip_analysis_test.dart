// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';

/// Decodes and analyses, on a real phone, every clip in the app's internal
/// `files/clips/` folder, and reports START, shots and how long each step
/// took. Timings are only meaningful in profile mode.
///
/// A profile build isn't debuggable, so copy the clips in with a debug build
/// first; the profile build installs over it and keeps them:
///
///     flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
///     adb push clip.mp4 /data/local/tmp/clip.mp4
///     adb shell "cat /data/local/tmp/clip.mp4 | run-as cc.jami.simpleshottimer \
///       sh -c 'mkdir -p files/clips && cat > files/clips/clip.mp4'"
///     flutter drive --profile --driver=test_driver/integration_test.dart \
///       --target=integration_test/clip_analysis_test.dart -d <device>
///
/// `flutter drive` uninstalls the app when it finishes, which deletes its data
/// and the clips. The report lands in build/integration_response_data.json.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('decodes and analyses the clips on the device', (tester) async {
    final files = await getApplicationSupportDirectory();
    final dir = Directory('${files.path}/clips');
    final clips = dir.existsSync()
        ? (dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.mp4'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    expect(clips, isNotEmpty, reason: 'push clips to ${dir.path} first');

    final source = ChannelClipAudioSource();
    // Not the cache folder: Android empties that under storage pressure, even
    // between the decode and the analysis.
    final pcmPath = '${files.path}/clip.pcm';
    final results = <Map<String, Object?>>[];
    for (final clip in clips) {
      final watch = Stopwatch()..start();
      final info = await source.probe(clip.path);
      final probeMs = watch.elapsedMilliseconds;
      watch.reset();
      final audio = await source.decode(clip.path, outputPath: pcmPath);
      final decodeMs = watch.elapsedMilliseconds;
      watch.reset();
      final analysis = await analyzePcmFile(pcmPath, audio.sampleRate);
      final analyzeMs = watch.elapsedMilliseconds;
      File(pcmPath).deleteSync();

      final result = <String, Object?>{
        'file': clip.uri.pathSegments.last,
        'audioMime': info.audioMime,
        'videoMime': info.videoMime,
        'colorTransfer': info.colorTransfer,
        'rotation': info.rotationDegrees,
        'frameRate': info.frameRate,
        'creationTime': info.creationTime?.toIso8601String(),
        'sampleRate': audio.sampleRate,
        'channels': audio.channelCount,
        'seconds': audio.durationSeconds,
        'firstSampleTimeUs': audio.firstSampleTimeUs,
        'probeMs': probeMs,
        'decodeMs': decodeMs,
        'analyzeMs': analyzeMs,
        'start': analysis.startSeconds,
        'shots': analysis.stringShotSeconds,
        'allShots': analysis.shotSeconds,
        'tones': [
          for (final t in analysis.tones)
            {'onset': t.onsetSeconds, 'end': t.endSeconds, 'hz': t.frequencyHz},
        ],
      };
      results.add(result);
      debugPrint('clip ${result['file']}: '
          '${audio.durationSeconds.toStringAsFixed(1)} s, decode $decodeMs ms, '
          'analyse $analyzeMs ms, START ${analysis.startSeconds}, '
          '${analysis.stringShotSeconds.length} shots');
    }
    binding.reportData = {'clips': results};
  });
}
