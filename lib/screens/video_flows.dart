// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';

import '../models/timer_string.dart';
import '../services/video/clip_check.dart';
import '../services/video/clip_picker.dart';
import 'video_import_screen.dart';

/// Imports a video from [source]: the import screen opens the picker right
/// away and, once the clip is analysed, replaces itself with the editor.
/// [reopen] is the saved string "Choose video again" reopens.
Future<void> startVideoImport(
  BuildContext context,
  ClipSource source, {
  TimerString? reopen,
}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      // No transition: the picker covers it at once, and backing out of
      // the picker shows the tab again without a screen sliding away.
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          VideoImportScreen(source: source, reopen: reopen),
    ));

/// "Choose video again" in Review: pick the clip a saved video string was
/// made from and correct its markers again.
Future<void> chooseVideoAgain(BuildContext context, TimerString saved) =>
    startVideoImport(context, ClipSource.photos, reopen: saved);

String clipProblemKey(ClipProblem problem) => 'video.problem.${problem.name}';
