// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'dart:io';

import 'package:flutter/services.dart';

/// Loads Roboto (the Android font) from the Flutter SDK for widget tests
/// that measure text: the test font's square glyphs are far wider than real
/// text. The SDK's file names are capitalised, which Windows ignores and
/// Linux (CI) does not.
Future<void> loadRoboto() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final bytes = File('$fonts/Roboto-$weight.ttf').readAsBytesSync();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await roboto.load();
}
