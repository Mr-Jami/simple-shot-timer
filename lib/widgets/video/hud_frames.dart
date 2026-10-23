// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/video/clip_exporter.dart';
import '../../services/video/export_plan.dart';
import '../../services/video/hud.dart';
import '../../utils/cancel_token.dart';
import 'hud_painter.dart';

/// Draws the overlay images an export of [plan] needs, under [dir]:
///
/// - `box/`: the corner overlay; a still before START, then one image per
///   video frame while the clock runs and the last shot ticks;
/// - `card/` (when the end card shows): nothing, then its fade, one image
///   per frame, until it is fully there.
///
/// Each image starts half a frame early: frame times arrive rounded, and a
/// frame must never pick up the previous image. Raw RGBA with zlib, not
/// PNG: about six times faster to make. [onProgress] gets 0..1.
Future<List<OverlaySequence>> renderHudFrames({
  required Directory dir,
  required ExportPlan plan,
  required HudString string,
  required HudOptions options,
  required HudLabels labels,
  ui.Image? logo,
  void Function(double fraction)? onProgress,
  CancelToken? cancel,
}) async {
  final layout = HudLayout(plan.frame, options);
  final frameMs = 1000 / plan.fps;

  /// Clip times of the frames from [fromMs] up to the first one past
  /// [toMs], so the last image shows the settled state.
  List<int> frames(int fromMs, int toMs) => [
        for (var k = (fromMs / frameMs).ceil(); (k - 1) * frameMs <= toMs; k++)
          (k * frameMs).round(),
      ];

  final boxTimes = [
    plan.startMs,
    ...frames(string.startMs, string.endMs + HudMoment.tickMs),
  ];
  final withCard = options.endCard && string.shotCount > 0;
  final cardFrom = string.endMs + HudMoment.endCardDelayMs;
  final cardTimes = withCard
      ? [plan.startMs, ...frames(cardFrom, cardFrom + HudMoment.endCardFadeMs)]
      : const <int>[];

  // A little room around the box for the clock's outline.
  final bleed = (0.2 * layout.unit).ceilToDouble();
  final box = layout.box.inflate(bleed);
  final card = layout.card;
  final total = boxTimes.length + cardTimes.length;
  var done = 0;
  final zlib = ZLibCodec(level: 1);

  Future<void> draw(String folder, int index, int clipMs, Rect rect) async {
    if (cancel?.isCancelled ?? false) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final m = HudMoment.at(string, clipMs, endCard: options.endCard);
    if (folder == 'box') {
      canvas.translate(bleed, bleed);
      paintHudBox(canvas, layout, string, options, m, labels, logo: logo);
    } else {
      paintEndCard(canvas, layout, string, labels, m.endCard);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(rect.width.ceil(), rect.height.ceil());
    picture.dispose();
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    await File('${dir.path}/$folder/$index.z')
        .writeAsBytes(zlib.encode(rgba!.buffer.asUint8List()));
    onProgress?.call(++done / total);
  }

  final jobs = [
    for (final (i, t) in boxTimes.indexed) () => draw('box', i, t, box),
    for (final (i, t) in cardTimes.indexed) () => draw('card', i, t, card),
  ];
  await Directory('${dir.path}/box').create(recursive: true);
  if (withCard) await Directory('${dir.path}/card').create(recursive: true);
  // A few in flight: the rasterising and the encoding run off the UI
  // thread, so they overlap.
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length && !(cancel?.isCancelled ?? false)) {
      await jobs[next++]();
    }
  }

  await Future.wait([for (var w = 0; w < 4; w++) worker()]);
  if (cancel?.isCancelled ?? false) {
    throw const ExportException(ExportError.cancelled);
  }

  List<int> outputTimes(List<int> clipTimes) => [
        for (final (i, t) in clipTimes.indexed)
          i == 0
              ? 0
              : math.max(1, ((t - plan.startMs - frameMs / 2) * 1000).round()),
      ];
  final frame = plan.frame;
  return [
    OverlaySequence(
      dir: '${dir.path}/box',
      width: box.width.ceil(),
      height: box.height.ceil(),
      timesUs: outputTimes(boxTimes),
      x: box.left / frame.width,
      y: box.top / frame.height,
    ),
    if (withCard)
      OverlaySequence(
        dir: '${dir.path}/card',
        width: card.width.ceil(),
        height: card.height.ceil(),
        timesUs: outputTimes(cardTimes),
        x: card.left / frame.width,
        y: card.top / frame.height,
      ),
  ];
}
