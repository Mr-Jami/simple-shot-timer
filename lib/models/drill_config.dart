import 'package:flutter/widgets.dart';

import '../i18n/app_localizations.dart';
import 'app_settings.dart';
import 'enums.dart';

/// The subset of [AppSettings] that defines a drill: mode, start delay and
/// par/stage timing. Detection, beep, display, locale and history settings
/// are deliberately not part of it.
///
/// This is the one definition of "drill configuration" in the app (issue
/// #24). Any new AppSettings field that shapes a drill must be added here,
/// to [fromSettings], [applyTo], [toMap]/[fromMap] and the equality members,
/// or saved drills would silently drop it.
class DrillConfig {
  const DrillConfig({
    required this.drillMode,
    required this.delayMode,
    required this.fixedDelayMs,
    required this.randomDelayMinMs,
    required this.randomDelayMaxMs,
    required this.parDurationMs,
    required this.parRepeatCount,
    required this.parIntervalMs,
    required this.stageDurationMs,
  });

  /// Snapshot of the drill fields of [s].
  factory DrillConfig.fromSettings(AppSettings s) => DrillConfig(
        drillMode: s.drillMode,
        delayMode: s.delayMode,
        fixedDelayMs: s.fixedDelayMs,
        randomDelayMinMs: s.randomDelayMinMs,
        randomDelayMaxMs: s.randomDelayMaxMs,
        parDurationMs: s.parDurationMs,
        parRepeatCount: s.parRepeatCount,
        parIntervalMs: s.parIntervalMs,
        stageDurationMs: s.stageDurationMs,
      );

  /// Tolerant decode in the style of `SettingsService.load`: a missing or
  /// wrong-typed value falls back to the app default, as does an unknown
  /// enum name. Ranges are not enforced here; the timer guards them at use.
  factory DrillConfig.fromMap(Map<String, Object?> map) {
    final d = defaults;
    int readInt(String key, int fallback) {
      final v = map[key];
      return v is num ? v.toInt() : fallback;
    }

    return DrillConfig(
      drillMode:
          DrillMode.values.asNameMap()[map['drill_mode']] ?? d.drillMode,
      delayMode:
          DelayMode.values.asNameMap()[map['delay_mode']] ?? d.delayMode,
      fixedDelayMs: readInt('fixed_delay_ms', d.fixedDelayMs),
      randomDelayMinMs: readInt('random_delay_min_ms', d.randomDelayMinMs),
      randomDelayMaxMs: readInt('random_delay_max_ms', d.randomDelayMaxMs),
      parDurationMs: readInt('par_duration_ms', d.parDurationMs),
      parRepeatCount: readInt('par_repeat_count', d.parRepeatCount),
      parIntervalMs: readInt('par_interval_ms', d.parIntervalMs),
      stageDurationMs: readInt('stage_duration_ms', d.stageDurationMs),
    );
  }

  /// What a fresh install runs with.
  static final DrillConfig defaults =
      DrillConfig.fromSettings(const AppSettings());

  final DrillMode drillMode;
  final DelayMode delayMode;
  final int fixedDelayMs;
  final int randomDelayMinMs;
  final int randomDelayMaxMs;
  final int parDurationMs;
  final int parRepeatCount;
  final int parIntervalMs;
  final int stageDurationMs;

  /// Returns [s] with only the drill fields replaced; every other setting
  /// keeps its current value.
  AppSettings applyTo(AppSettings s) => s.copyWith(
        drillMode: drillMode,
        delayMode: delayMode,
        fixedDelayMs: fixedDelayMs,
        randomDelayMinMs: randomDelayMinMs,
        randomDelayMaxMs: randomDelayMaxMs,
        parDurationMs: parDurationMs,
        parRepeatCount: parRepeatCount,
        parIntervalMs: parIntervalMs,
        stageDurationMs: stageDurationMs,
      );

  /// Keys match the SharedPreferences keys in `SettingsService` so the two
  /// serialisations of the same fields read alike.
  Map<String, Object?> toMap() => {
        'drill_mode': drillMode.name,
        'delay_mode': delayMode.name,
        'fixed_delay_ms': fixedDelayMs,
        'random_delay_min_ms': randomDelayMinMs,
        'random_delay_max_ms': randomDelayMaxMs,
        'par_duration_ms': parDurationMs,
        'par_repeat_count': parRepeatCount,
        'par_interval_ms': parIntervalMs,
        'stage_duration_ms': stageDurationMs,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrillConfig &&
          drillMode == other.drillMode &&
          delayMode == other.delayMode &&
          fixedDelayMs == other.fixedDelayMs &&
          randomDelayMinMs == other.randomDelayMinMs &&
          randomDelayMaxMs == other.randomDelayMaxMs &&
          parDurationMs == other.parDurationMs &&
          parRepeatCount == other.parRepeatCount &&
          parIntervalMs == other.parIntervalMs &&
          stageDurationMs == other.stageDurationMs;

  @override
  int get hashCode => Object.hash(
        drillMode,
        delayMode,
        fixedDelayMs,
        randomDelayMinMs,
        randomDelayMaxMs,
        parDurationMs,
        parRepeatCount,
        parIntervalMs,
        stageDurationMs,
      );

  @override
  String toString() => 'DrillConfig(${toMap()})';
}

/// Localized descriptions of a [DrillConfig], in the style of the `labelFor`
/// extensions in `enums.dart`.
extension DrillConfigLabels on DrillConfig {
  /// One short label per aspect, e.g. ["Par mode", "Random delay",
  /// "Par 2.0s x 4"]. Rendered as the home summary chips and joined for list
  /// subtitles, so a drill reads the same everywhere.
  List<String> chipLabels(BuildContext context) => [
        context.tr('home.modeChip', args: {'mode': drillMode.labelFor(context)}),
        _delayLabel(context),
        if (drillMode == DrillMode.par) _parLabel(context),
        if (drillMode == DrillMode.stage) _stageLabel(context),
      ];

  /// [chipLabels] on a single line.
  String summary(BuildContext context) => chipLabels(context).join(' · ');

  String _delayLabel(BuildContext context) {
    switch (delayMode) {
      case DelayMode.instant:
        return context.tr('home.delayInstant');
      case DelayMode.fixed:
        return context.tr('home.delayFixed',
            args: {'seconds': (fixedDelayMs / 1000).toStringAsFixed(1)});
      case DelayMode.random:
        return context.tr('home.delayRandom');
    }
  }

  String _parLabel(BuildContext context) {
    final dur = (parDurationMs / 1000).toStringAsFixed(1);
    return parRepeatCount == 1
        ? context.tr('home.parSingle', args: {'duration': dur})
        : context.tr('home.parRepeated',
            args: {'duration': dur, 'count': parRepeatCount});
  }

  String _stageLabel(BuildContext context) => context.tr(
        'home.stage',
        args: {'duration': (stageDurationMs / 1000).round()},
      );
}
