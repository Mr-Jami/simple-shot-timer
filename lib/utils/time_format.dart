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
