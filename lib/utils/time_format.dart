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

/// Whole minutes and seconds, "1:05", or past an hour "1:02:05".
String formatMinutes(int ms) {
  final s = ms ~/ 1000;
  String two(int n) => n.toString().padLeft(2, '0');
  return s >= 3600
      ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}'
      : '${s ~/ 60}:${two(s % 60)}';
}
