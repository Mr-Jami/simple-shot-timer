// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/video/clip_analyzer_runner.dart';
import '../services/video/clip_audio_source.dart';
import '../services/video/clip_exporter.dart';
import '../services/video/clip_picker.dart';
import '../services/video/hud.dart';
import '../services/video/hud_frames.dart';
import '../services/video/hud_logo.dart';
import '../services/video/video_gallery.dart';
import '../services/video/video_string_store.dart';
import '../services/video/video_work_dir.dart';
import 'providers.dart';
import 'settings_provider.dart';

// The video feature depends on these ports rather than on the plugins and
// channels behind them, so tests can drive an import or an edit with fakes
// (see video_import_test.dart).
final clipAudioSourceProvider =
    Provider<ClipAudioSource>((ref) => ChannelClipAudioSource());
final clipPickerProvider = Provider<ClipPicker>((ref) => PluginClipPicker());
final clipAnalyzerProvider =
    Provider<ClipAnalyzerRunner>((ref) => const IsolateClipAnalyzer());
final videoWorkDirProvider = Provider<VideoWorkDir>((ref) => VideoWorkDir());
final videoStringStoreProvider =
    Provider<VideoStringStore>((ref) => ref.watch(databaseProvider));

final clipExporterProvider =
    Provider<ClipExporter>((ref) => ChannelClipExporter());
final videoGalleryProvider =
    Provider<VideoGallery>((ref) => const PluginVideoGallery());

final hudFrameRendererProvider =
    Provider<HudFrameRenderer>((ref) => renderHudFrames);

/// The overlay badge's mark, decoded once and kept: the Video tab is built
/// at start-up, so the image is ready before any overlay first shows.
final hudLogoProvider = FutureProvider<ui.Image>((ref) => loadHudLogo());

/// The overlay's style, corner and end card, as last chosen.
final hudOptionsProvider = Provider<HudOptions>(
  (ref) => ref.watch(settingsProvider.select((s) => HudOptions(
        style: s.hudStyle,
        corner: s.hudCorner,
        endCard: s.hudEndCard,
      ))),
);
