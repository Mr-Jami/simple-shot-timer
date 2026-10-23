// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../utils/cancel_token.dart';
import 'clip_exporter.dart';
import 'export_plan.dart';
import 'hud.dart';
import 'hud_painter.dart';

/// Draws an export's overlay images ([renderHudFrames]). A port, so the
/// export can be tested without rasterising.
typedef HudFrameRenderer = Future<List<OverlaySequence>> Function({
  required Directory dir,
  required ExportPlan plan,
  required HudString string,
  required HudOptions options,
  required HudLabels labels,
  ui.Image? logo,
  void Function(double fraction)? onProgress,
  CancelToken? cancel,
});

/// One sequence of overlay images: its [folder], where it sits in the frame
/// ([rect]), the clip times of its images, and how to paint one.
typedef _Sequence = ({
  String folder,
  ui.Rect rect,
  List<int> times,
  void Function(ui.Canvas canvas, HudMoment moment) paint,
});

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

  // A little room around the box for the clock's outline.
  final bleed = (0.2 * layout.unit).ceilToDouble();
  final cardFrom = string.endMs + HudMoment.endCardDelayMs;
  final sequences = <_Sequence>[
    (
      folder: 'box',
      rect: layout.box.inflate(bleed),
      times: [
        plan.startMs,
        ...frames(string.startMs, string.endMs + HudMoment.tickMs),
      ],
      paint: (canvas, m) {
        canvas.translate(bleed, bleed);
        paintHudBox(canvas, layout, string, options, m, labels, logo: logo);
      },
    ),
    if (options.endCard && string.shotCount > 0)
      (
        folder: 'card',
        rect: layout.card,
        times: [
          plan.startMs,
          ...frames(cardFrom, cardFrom + HudMoment.endCardFadeMs),
        ],
        paint: (canvas, m) =>
            paintEndCard(canvas, layout, string, labels, m.endCard),
      ),
  ];

  final total = sequences.fold(0, (n, q) => n + q.times.length);
  var done = 0;
  final zlib = ZLibCodec(level: 1);
  for (final q in sequences) {
    await Directory('${dir.path}/${q.folder}').create(recursive: true);
  }
  await _runAll(
    [
      for (final q in sequences)
        for (final (i, t) in q.times.indexed)
          () async {
            final m = HudMoment.at(string, t, endCard: options.endCard);
            final rgba = await _rasterise(q.rect.size, (c) => q.paint(c, m));
            await File('${dir.path}/${q.folder}/$i.z')
                .writeAsBytes(zlib.encode(rgba));
            onProgress?.call(++done / total);
          },
    ],
    cancel: cancel,
  );
  if (cancel?.isCancelled ?? false) {
    throw const ExportException(ExportError.cancelled);
  }

  final frame = plan.frame;
  return [
    for (final q in sequences)
      OverlaySequence(
        dir: '${dir.path}/${q.folder}',
        width: q.rect.width.ceil(),
        height: q.rect.height.ceil(),
        timesUs: [
          for (final (i, t) in q.times.indexed)
            i == 0
                ? 0
                : math.max(
                    1, ((t - plan.startMs - frameMs / 2) * 1000).round()),
        ],
        x: q.rect.left / frame.width,
        y: q.rect.top / frame.height,
      ),
  ];
}

/// What [draw] paints, as an image of [size] in raw premultiplied RGBA.
Future<Uint8List> _rasterise(
    ui.Size size, void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  picture.dispose();
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return rgba!.buffer.asUint8List();
}

/// Runs [jobs] a few at a time: the rasterising and the encoding run off the
/// UI thread, so they overlap. Stops starting new ones once [cancel] fires.
Future<void> _runAll(
  List<Future<void> Function()> jobs, {
  int workers = 4,
  CancelToken? cancel,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length && !(cancel?.isCancelled ?? false)) {
      await jobs[next++]();
    }
  }

  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
}
