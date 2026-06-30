import 'enums.dart';

class AppSettings {
  const AppSettings({
    this.sensitivityPercent = 15,
    this.echoFilterMs = 80,
    this.bandFilterEnabled = true,
    this.bandLowHz = 300,
    this.bandHighHz = 6000,
    this.beepVolume = 0.9,
    this.audioLatencyOffsetMs = 0,
    this.delayMode = DelayMode.random,
    this.fixedDelayMs = 2000,
    this.randomDelayMinMs = 1000,
    this.randomDelayMaxMs = 4000,
    this.parDurationMs = 2000,
    this.parRepeatCount = 1,
    this.parIntervalMs = 5000,
    this.stageDurationMs = 60000,
    this.drillMode = DrillMode.standard,
    this.keepScreenAwake = true,
    this.visualFlash = true,
    this.hapticOnBeep = false,
    this.themeMode = AppThemeMode.system,
    this.historyCap = 500,
    this.localeCode,
  });

  /// 0–100 user-facing sensitivity. Higher = more sensitive.
  /// Threshold passed to the detector is `1 - sensitivityPercent / 100`.
  final int sensitivityPercent;
  final int echoFilterMs;

  /// Whether to band-pass the mic signal before peak detection. Rejects loud
  /// non-shot sounds that sit mostly outside the gunshot energy band.
  final bool bandFilterEnabled;

  /// Low-cut (high-pass) frequency in Hz. Anything below is attenuated.
  final int bandLowHz;

  /// High-cut (low-pass) frequency in Hz. Anything above is attenuated.
  final int bandHighHz;

  final double beepVolume;

  /// Extra latency (ms) to subtract from shot times on top of the acoustic
  /// auto-calibration — for output delay the mic can't measure itself, e.g. a
  /// Bluetooth speaker the phone mic doesn't pick up. 0 = rely purely on the
  /// measured beep onset. See issue #18.
  final int audioLatencyOffsetMs;

  final DelayMode delayMode;
  final int fixedDelayMs;
  final int randomDelayMinMs;
  final int randomDelayMaxMs;
  final int parDurationMs;

  /// Number of par beeps fired per string (only when [drillMode] is
  /// [DrillMode.par]). 1 = a single par beep, 2..N = beep at every multiple of
  /// [parDurationMs] up to N beeps.
  final int parRepeatCount;

  /// Rest delay inserted between consecutive par beeps. 0 = back-to-back
  /// (legacy behavior). With par=2s, repeat=4, interval=4s the beeps fire at
  /// 2s, 8s, 14s, 20s.
  final int parIntervalMs;

  /// Duration of a single Stage drill window. Stage = "long par" — one beep
  /// fires at this point. Slider goes in integer seconds.
  final int stageDurationMs;
  final DrillMode drillMode;
  final bool keepScreenAwake;
  final bool visualFlash;
  final bool hapticOnBeep;
  final AppThemeMode themeMode;
  final int historyCap;

  /// Two-letter language code (e.g. `en`, `de`). `null` follows the device.
  final String? localeCode;

  static const int historyCapMin = 50;
  static const int historyCapMax = 5000;
  static const int parRepeatMin = 1;
  static const int parRepeatMax = 20;
  static const int stageDurationMinMs = 1000;
  static const int stageDurationMaxMs = 200000;
  static const int bandLowMinHz = 50;
  static const int bandLowMaxHz = 2000;
  static const int bandHighMinHz = 1000;
  static const int bandHighMaxHz = 12000;
  static const int audioLatencyOffsetMinMs = 0;
  static const int audioLatencyOffsetMaxMs = 500;

  /// Amplitude threshold (0..1) derived from [sensitivityPercent].
  double get detectionThreshold =>
      ((100 - sensitivityPercent.clamp(0, 100)) / 100).clamp(0.0, 1.0);

  AppSettings copyWith({
    int? sensitivityPercent,
    int? echoFilterMs,
    bool? bandFilterEnabled,
    int? bandLowHz,
    int? bandHighHz,
    double? beepVolume,
    int? audioLatencyOffsetMs,
    DelayMode? delayMode,
    int? fixedDelayMs,
    int? randomDelayMinMs,
    int? randomDelayMaxMs,
    int? parDurationMs,
    int? parRepeatCount,
    int? parIntervalMs,
    int? stageDurationMs,
    DrillMode? drillMode,
    bool? keepScreenAwake,
    bool? visualFlash,
    bool? hapticOnBeep,
    AppThemeMode? themeMode,
    int? historyCap,
    String? localeCode,
    bool clearLocaleCode = false,
  }) =>
      AppSettings(
        sensitivityPercent: sensitivityPercent ?? this.sensitivityPercent,
        echoFilterMs: echoFilterMs ?? this.echoFilterMs,
        bandFilterEnabled: bandFilterEnabled ?? this.bandFilterEnabled,
        bandLowHz: bandLowHz ?? this.bandLowHz,
        bandHighHz: bandHighHz ?? this.bandHighHz,
        beepVolume: beepVolume ?? this.beepVolume,
        audioLatencyOffsetMs:
            audioLatencyOffsetMs ?? this.audioLatencyOffsetMs,
        delayMode: delayMode ?? this.delayMode,
        fixedDelayMs: fixedDelayMs ?? this.fixedDelayMs,
        randomDelayMinMs: randomDelayMinMs ?? this.randomDelayMinMs,
        randomDelayMaxMs: randomDelayMaxMs ?? this.randomDelayMaxMs,
        parDurationMs: parDurationMs ?? this.parDurationMs,
        parRepeatCount: parRepeatCount ?? this.parRepeatCount,
        parIntervalMs: parIntervalMs ?? this.parIntervalMs,
        stageDurationMs: stageDurationMs ?? this.stageDurationMs,
        drillMode: drillMode ?? this.drillMode,
        keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
        visualFlash: visualFlash ?? this.visualFlash,
        hapticOnBeep: hapticOnBeep ?? this.hapticOnBeep,
        themeMode: themeMode ?? this.themeMode,
        historyCap: historyCap ?? this.historyCap,
        localeCode:
            clearLocaleCode ? null : (localeCode ?? this.localeCode),
      );
}
