// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// ignore_for_file: depend_on_referenced_packages, avoid_print, invalid_use_of_visible_for_testing_member
// Renders the real video editor for the store screenshot: a clip's actual
// analysis, the app's dark theme and fonts, and a fake video platform whose
// picture is the clip's frame at the playhead, so the editor draws its own
// overlay preview on it. The clip stays out of the repo: pass its path.
//
//   flutter test branding/store-listing/render/editor_shot_test.dart
//     --dart-define=CLIP=.local/video-shot-timer/clips/user/dji_03.mp4
//     --dart-define=AT_MS=15060 --dart-define=PLATFORM=android|ios
//     --dart-define=ZOOM=0.42 --dart-define=SCROLL=186 --dart-define=LOCALE=de
//     --dart-define=OUT=branding/store-listing/assets/video-editor.png
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_shot_timer/i18n/app_localizations.dart';
import 'package:simple_shot_timer/models/timer_string.dart';
import 'package:simple_shot_timer/providers/clip_editor_provider.dart';
import 'package:simple_shot_timer/providers/providers.dart';
import 'package:simple_shot_timer/providers/video_providers.dart';
import 'package:simple_shot_timer/screens/video_editor_screen.dart';
import 'package:simple_shot_timer/services/video/analyzed_clip.dart';
import 'package:simple_shot_timer/services/video/clip_analyzer.dart';
import 'package:simple_shot_timer/services/video/clip_audio_source.dart';
import 'package:simple_shot_timer/services/video/video_string_store.dart';
import 'package:simple_shot_timer/services/video/video_work_dir.dart';
import 'package:simple_shot_timer/theme/app_theme.dart';
import 'package:simple_shot_timer/widgets/timeline/shot_timeline.dart';
import 'package:simple_shot_timer/widgets/timeline/timeline_minimap.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

const clip = String.fromEnvironment('CLIP');
const atMs = int.fromEnvironment('AT_MS');
const platform = String.fromEnvironment('PLATFORM', defaultValue: 'android');
const out = String.fromEnvironment('OUT');

class _Store implements VideoStringStore {
  @override
  Future<TimerString> insertString(TimerString s,
          {required int historyCap}) async =>
      s.copyWith(id: 1);
  @override
  Future<void> updateVideoString(TimerString s) async {}
  @override
  Future<void> deleteString(int id) async {}
}

class _Session extends VideoSession {
  _Session() : super(Directory('session'));
  @override
  String get clipPath => clip;
  @override
  Future<void> dispose() async {}
}

/// A "video" that is one still picture.
class _Still extends VideoPlayerPlatform {
  _Still(this.size, this.duration);
  final Size size;
  final Duration duration;
  final picture = ValueNotifier<Uint8List?>(null);
  var _position = Duration.zero;

  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource dataSource) async => 1;
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final c = StreamController<VideoEvent>();
    c.add(VideoEvent(
        eventType: VideoEventType.initialized, duration: duration, size: size));
    return c.stream;
  }

  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _position = position;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => _position;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Widget buildView(int playerId) => _view();
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => _view();

  Widget _view() => ValueListenableBuilder<Uint8List?>(
        valueListenable: picture,
        builder: (_, bytes, __) => bytes == null
            ? const ColoredBox(color: Colors.black)
            : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
      );
}

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final ios = platform == 'ios';

  setUpAll(() async {
    final sdk =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = [
      for (final w in ['Regular', 'Medium', 'Bold']) '$sdk/Roboto-$w.ttf',
    ];
    // What Chrome on this machine draws for -apple-system in the HTML.
    const segoe = [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/seguisb.ttf',
      'C:/Windows/Fonts/segoeuib.ttf',
    ];
    await _font('Roboto', roboto);
    await _font('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
    await _font('Montserrat', ['assets/fonts/Montserrat-ExtraBoldItalic.ttf']);
    // The overlay's numbers name no family: the phone's system font. In a
    // test the engine asks for the host's defaults instead.
    for (final family in ['Segoe UI', 'Arial', 'sans-serif', 'FlutterTest']) {
      await _font(family, ios ? segoe : roboto);
    }
    if (ios) {
      for (final family in [
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.SF Pro Text',
        '.SF Pro Display',
        '.SF UI Text',
        '.SF UI Display',
      ]) {
        await _font(family, segoe);
      }
    }
  });

  testWidgets('editor screenshot', (tester) async {
    if (ios) debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final logical = ios ? const Size(393, 852) : const Size(390, 845);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = logical * 3;
    tester.view.padding = FakeViewPadding(
        top: (ios ? 59 : 24) * 3.0, bottom: (ios ? 34 : 20) * 3.0);
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);

    // The clip's sound as the app reads it: the first channel.
    final pcm = (await tester.runAsync(() async {
      final r = await Process.run(
          'ffmpeg',
          [
            '-loglevel', 'error', '-i', clip, '-vn', '-map', '0:a:0', //
            '-af', 'pan=mono|c0=c0', '-ar', '48000', '-f', 's16le', '-',
          ],
          stdoutEncoding: null);
      final bytes = r.stdout as List<int>;
      return Uint8List.fromList(bytes).buffer.asInt16List();
    }))!;
    final analysis = analyzePcm(pcm, 48000);
    final durationMs = pcm.length * 1000 ~/ 48000;
    print('START ${analysis.startSeconds} shots ${analysis.stringShotSeconds}');

    final still = _Still(const Size(1080, 1920), Duration(milliseconds: durationMs));
    VideoPlayerPlatform.instance = still;

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      videoStringStoreProvider.overrideWithValue(_Store()),
    ]);
    addTearDown(container.dispose);
    final args = ClipEditorArgs(
      clip: AnalyzedClip(
        info: ClipInfo(
          hasAudio: true,
          durationMs: durationMs,
          videoMime: 'video/hevc',
          width: 1080,
          height: 1920,
          frameRate: 50,
        ),
        analysis: analysis,
        audioOriginMs: 0,
      ),
      session: _Session(),
      importedAt: DateTime(2026, 10, 23, 14),
    );
    final shot = GlobalKey();
    final theme = buildAppTheme(Brightness.dark, highContrast: false);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale(String.fromEnvironment('LOCALE', defaultValue: 'en')),
          supportedLocales: [for (final l in kSupportedAppLocales) l.locale],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VideoEditorScreen(args: args),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; find.text('open').evaluate().isEmpty && i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The HUD logo decodes off the test clock.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    // Jump to the moment through the minimap, as a tap would.
    final map = tester.getRect(find.byType(TimelineMinimap));
    await tester.tapAt(Offset(map.left + map.width * atMs / durationMs, map.center.dy));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Zoom the timeline (1 = as it opens, 150 px/s), as a pinch would.
    const zoom = String.fromEnvironment('ZOOM', defaultValue: '1');
    if (zoom != '1') {
      tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller
        ..startDrag()
        ..zoom(double.parse(zoom), 0)
        ..endDrag(0);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    // Scroll the details so the stats show whole.
    const scroll = int.fromEnvironment('SCROLL', defaultValue: 110);
    await tester.drag(find.byType(ListView).last, Offset(0, -scroll.toDouble()));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final timeline =
        tester.widget<ShotTimeline>(find.byType(ShotTimeline)).controller;
    final playhead = timeline.playheadMs.round();
    print('playhead $playhead ms');

    // The frame at the playhead, upright, as the player would show it.
    final frame = (await tester.runAsync(() async {
      final r = await Process.run(
          'ffmpeg',
          [
            '-loglevel', 'error', '-ss', (playhead / 1000).toStringAsFixed(3), //
            '-i', clip, '-frames:v', '1', '-f', 'image2', '-c:v', 'png', '-',
          ],
          stdoutEncoding: null);
      final bytes = Uint8List.fromList(r.stdout as List<int>);
      final context = tester.element(find.byType(VideoEditorScreen));
      await precacheImage(MemoryImage(bytes), context);
      return bytes;
    }))!;
    still.picture.value = frame;
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    final png = (await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }))!;
    File(out).writeAsBytesSync(png);
    print('wrote $out');
    debugDefaultTargetPlatformOverride = null;
  });
}
