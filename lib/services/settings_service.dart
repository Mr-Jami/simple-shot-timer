import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/enums.dart';

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kSensitivity = 'sensitivity_percent';
  static const _kEchoFilter = 'echo_filter_ms';
  static const _kBandEnabled = 'band_filter_enabled';
  static const _kBandLow = 'band_low_hz';
  static const _kBandHigh = 'band_high_hz';
  static const _kBeepVolume = 'beep_volume';
  static const _kDelayMode = 'delay_mode';
  static const _kFixedDelay = 'fixed_delay_ms';
  static const _kRandomMin = 'random_delay_min_ms';
  static const _kRandomMax = 'random_delay_max_ms';
  static const _kParDuration = 'par_duration_ms';
  static const _kParRepeatCount = 'par_repeat_count';
  static const _kParInterval = 'par_interval_ms';
  static const _kStageDuration = 'stage_duration_ms';
  static const _kDrillMode = 'drill_mode';
  static const _kKeepAwake = 'keep_screen_awake';
  static const _kVisualFlash = 'visual_flash';
  static const _kHaptic = 'haptic_on_beep';
  static const _kTheme = 'theme_mode';
  static const _kHistoryCap = 'history_cap';
  static const _kLocale = 'locale_code';

  AppSettings load() {
    const defaults = AppSettings();
    return AppSettings(
      sensitivityPercent:
          _prefs.getInt(_kSensitivity) ?? defaults.sensitivityPercent,
      echoFilterMs: _prefs.getInt(_kEchoFilter) ?? defaults.echoFilterMs,
      bandFilterEnabled:
          _prefs.getBool(_kBandEnabled) ?? defaults.bandFilterEnabled,
      bandLowHz: _prefs.getInt(_kBandLow) ?? defaults.bandLowHz,
      bandHighHz: _prefs.getInt(_kBandHigh) ?? defaults.bandHighHz,
      beepVolume: _prefs.getDouble(_kBeepVolume) ?? defaults.beepVolume,
      delayMode: _readEnum(_kDelayMode, DelayMode.values, defaults.delayMode),
      fixedDelayMs: _prefs.getInt(_kFixedDelay) ?? defaults.fixedDelayMs,
      randomDelayMinMs:
          _prefs.getInt(_kRandomMin) ?? defaults.randomDelayMinMs,
      randomDelayMaxMs:
          _prefs.getInt(_kRandomMax) ?? defaults.randomDelayMaxMs,
      parDurationMs: _prefs.getInt(_kParDuration) ?? defaults.parDurationMs,
      parRepeatCount:
          _prefs.getInt(_kParRepeatCount) ?? defaults.parRepeatCount,
      parIntervalMs: _prefs.getInt(_kParInterval) ?? defaults.parIntervalMs,
      stageDurationMs:
          _prefs.getInt(_kStageDuration) ?? defaults.stageDurationMs,
      drillMode: _readEnum(_kDrillMode, DrillMode.values, defaults.drillMode),
      keepScreenAwake: _prefs.getBool(_kKeepAwake) ?? defaults.keepScreenAwake,
      visualFlash: _prefs.getBool(_kVisualFlash) ?? defaults.visualFlash,
      hapticOnBeep: _prefs.getBool(_kHaptic) ?? defaults.hapticOnBeep,
      themeMode: _readEnum(_kTheme, AppThemeMode.values, defaults.themeMode),
      historyCap: _prefs.getInt(_kHistoryCap) ?? defaults.historyCap,
      localeCode: _prefs.getString(_kLocale),
    );
  }

  Future<void> save(AppSettings s) async {
    await Future.wait([
      _prefs.setInt(_kSensitivity, s.sensitivityPercent),
      _prefs.setInt(_kEchoFilter, s.echoFilterMs),
      _prefs.setBool(_kBandEnabled, s.bandFilterEnabled),
      _prefs.setInt(_kBandLow, s.bandLowHz),
      _prefs.setInt(_kBandHigh, s.bandHighHz),
      _prefs.setDouble(_kBeepVolume, s.beepVolume),
      _prefs.setString(_kDelayMode, s.delayMode.name),
      _prefs.setInt(_kFixedDelay, s.fixedDelayMs),
      _prefs.setInt(_kRandomMin, s.randomDelayMinMs),
      _prefs.setInt(_kRandomMax, s.randomDelayMaxMs),
      _prefs.setInt(_kParDuration, s.parDurationMs),
      _prefs.setInt(_kParRepeatCount, s.parRepeatCount),
      _prefs.setInt(_kParInterval, s.parIntervalMs),
      _prefs.setInt(_kStageDuration, s.stageDurationMs),
      _prefs.setString(_kDrillMode, s.drillMode.name),
      _prefs.setBool(_kKeepAwake, s.keepScreenAwake),
      _prefs.setBool(_kVisualFlash, s.visualFlash),
      _prefs.setBool(_kHaptic, s.hapticOnBeep),
      _prefs.setString(_kTheme, s.themeMode.name),
      _prefs.setInt(_kHistoryCap, s.historyCap),
      if (s.localeCode == null)
        _prefs.remove(_kLocale)
      else
        _prefs.setString(_kLocale, s.localeCode!),
    ]);
  }

  Future<void> reset() => _prefs.clear();

  T _readEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final raw = _prefs.getString(key);
    if (raw == null) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }
}
