// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

String formatSeconds(int ms, {int decimals = 2}) {
  if (ms < 0) return '-${formatSeconds(-ms, decimals: decimals)}';
  final seconds = ms / 1000.0;
  return seconds.toStringAsFixed(decimals);
}

String formatSplit(int? ms) {
  if (ms == null) return '--';
  return '${formatSeconds(ms)}s';
}

String formatClock(int ms) => formatSeconds(ms);
