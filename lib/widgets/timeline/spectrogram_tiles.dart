// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../services/video/spectrogram.dart';

/// The clip's spectrogram as images for the timeline: [tileFrames] frames
/// per tile, 0 to [maxHz] from bottom to top (shots are broadband and beeps
/// sit at 2 to 4 kHz, while phone and messenger audio holds little above
/// 12 kHz), quiet in [quiet] and loud in [loud] (the theme's paper and ink,
/// so it stays monochrome). Tiles are built when first asked for and a few
/// are kept; listeners hear when one is ready.
class SpectrogramTiles extends ChangeNotifier {
  SpectrogramTiles(
    this.spectrogram, {
    required ui.Color quiet,
    required ui.Color loud,
    this.tileFrames = 1024,
    this.keep = 24,
    double maxHz = 12000,
  })  : rows = (maxHz / spectrogram.binHz).ceil().clamp(1, Spectrogram.bins),
        _lut = _palette(spectrogram, quiet, loud);

  final Spectrogram spectrogram;
  final int tileFrames;
  final int keep;

  /// Frequency bins shown, from the lowest.
  final int rows;
  final Uint32List _lut;

  final _tiles = <int, ui.Image>{};
  final _building = <int>{};
  var _disposed = false;

  int get tileCount => (spectrogram.frameCount / tileFrames).ceil();

  /// The tile [index], or null while it is being built.
  ui.Image? tile(int index) {
    final image = _tiles.remove(index);
    if (image != null) {
      _tiles[index] = image; // Most recently used last.
      return image;
    }
    if (_building.add(index)) unawaited(_build(index));
    return null;
  }

  Future<void> _build(int index) async {
    const bins = Spectrogram.bins;
    final from = index * tileFrames;
    final width = (spectrogram.frameCount - from).clamp(0, tileFrames);
    if (width == 0) return;
    final pixels = Uint32List(width * rows);
    final v = spectrogram.values;
    for (var x = 0; x < width; x++) {
      final row = (from + x) * bins;
      for (var k = 0; k < rows; k++) {
        pixels[(rows - 1 - k) * width + x] = _lut[v[row + k]];
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.buffer.asUint8List(),
      width,
      rows,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    final image = await done.future;
    _building.remove(index);
    if (_disposed) {
      image.dispose();
      return;
    }
    _tiles[index] = image;
    while (_tiles.length > keep) {
      _tiles.remove(_tiles.keys.first)!.dispose();
    }
    notifyListeners();
  }

  /// One RGBA word per byte value: the clip's own levels spread between its
  /// 30th percentile (quiet) and its loudest 2 % (loud), lifted a little so
  /// the mid levels where shots ring out still read.
  static Uint32List _palette(Spectrogram s, ui.Color quiet, ui.Color loud) {
    final sample = <int>[
      for (var i = 0; i < s.values.length; i += 97) s.values[i],
    ]..sort();
    final low = sample.isEmpty ? 0 : sample[(sample.length * 0.3).floor()];
    final high = sample.isEmpty
        ? 255
        : sample[(sample.length * 0.98).floor().clamp(0, sample.length - 1)];
    final span = (high - low).clamp(1, 255);
    final lut = Uint32List(256);
    for (var v = 0; v < 256; v++) {
      final t = ((v - low) / span).clamp(0.0, 1.0);
      final c = ui.Color.lerp(quiet, loud, math.pow(t, 0.8).toDouble())!;
      int byte(double channel) => (channel * 255).round() & 0xFF;
      // rgba8888 in memory, read as a little-endian word.
      lut[v] = byte(c.r) | byte(c.g) << 8 | byte(c.b) << 16 | byte(c.a) << 24;
    }
    return lut;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _tiles.values) {
      image.dispose();
    }
    _tiles.clear();
    super.dispose();
  }
}
