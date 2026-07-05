# Graph Report - simple-shot-timer  (2026-07-05)

## Corpus Check
- 79 files · ~137,438 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 955 nodes · 1174 edges · 80 communities (53 shown, 27 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 9 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b9e8594e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Audio Capture & Shot Detection|Audio Capture & Shot Detection]]
- [[_COMMUNITY_App Bootstrap & Providers|App Bootstrap & Providers]]
- [[_COMMUNITY_App Settings Model|App Settings Model]]
- [[_COMMUNITY_History Screen|History Screen]]
- [[_COMMUNITY_Localization (i18n)|Localization (i18n)]]
- [[_COMMUNITY_Timer Provider Core|Timer Provider Core]]
- [[_COMMUNITY_CICD & Release Automation|CI/CD & Release Automation]]
- [[_COMMUNITY_FFT Utilities|FFT Utilities]]
- [[_COMMUNITY_SQLite Database Service|SQLite Database Service]]
- [[_COMMUNITY_Auto-Configure Analysis|Auto-Configure Analysis]]
- [[_COMMUNITY_iOS Runner (Swift)|iOS Runner (Swift)]]
- [[_COMMUNITY_Par Config Model|Par Config Model]]
- [[_COMMUNITY_Timer String Model|Timer String Model]]
- [[_COMMUNITY_Settings Screen Widgets|Settings Screen Widgets]]
- [[_COMMUNITY_Screen Theming & State Display|Screen Theming & State Display]]
- [[_COMMUNITY_Auto-Configure Screen|Auto-Configure Screen]]
- [[_COMMUNITY_Timer State Model|Timer State Model]]
- [[_COMMUNITY_Home Screen Widgets|Home Screen Widgets]]
- [[_COMMUNITY_Mic Test Screen|Mic Test Screen]]
- [[_COMMUNITY_Flash Overlay Widget|Flash Overlay Widget]]
- [[_COMMUNITY_History Provider|History Provider]]
- [[_COMMUNITY_App Root & Controls|App Root & Controls]]
- [[_COMMUNITY_Beep Onset Detector Tests|Beep Onset Detector Tests]]
- [[_COMMUNITY_Background Service|Background Service]]
- [[_COMMUNITY_Beep Onset Detector|Beep Onset Detector]]
- [[_COMMUNITY_Delay Test Suite|Delay Test Suite]]
- [[_COMMUNITY_Auto-Configure Screen State|Auto-Configure Screen State]]
- [[_COMMUNITY_Par Schedule Model|Par Schedule Model]]
- [[_COMMUNITY_Settings Provider|Settings Provider]]
- [[_COMMUNITY_Timer Run Lifecycle|Timer Run Lifecycle]]
- [[_COMMUNITY_Release Please Config|Release Please Config]]
- [[_COMMUNITY_Monochrome Theme|Monochrome Theme]]
- [[_COMMUNITY_Biquad Filters|Biquad Filters]]
- [[_COMMUNITY_Auto-Configure Tests|Auto-Configure Tests]]
- [[_COMMUNITY_Biquad Filter Tests|Biquad Filter Tests]]
- [[_COMMUNITY_Android Plugin Registrant|Android Plugin Registrant]]
- [[_COMMUNITY_iOS LLDB Debug Helper|iOS LLDB Debug Helper]]
- [[_COMMUNITY_Calibration Shot Model|Calibration Shot Model]]
- [[_COMMUNITY_Time Formatting Utils|Time Formatting Utils]]
- [[_COMMUNITY_App Branding Icon|App Branding Icon]]
- [[_COMMUNITY_String Provider|String Provider]]
- [[_COMMUNITY_Split Time Tests|Split Time Tests]]
- [[_COMMUNITY_Android MainActivity|Android MainActivity]]
- [[_COMMUNITY_Flutter Export Environment|Flutter Export Environment]]
- [[_COMMUNITY_Agent OS Standards Stub|Agent OS Standards Stub]]
- [[_COMMUNITY_iOS Launch Screen Note|iOS Launch Screen Note]]
- [[_COMMUNITY_Misc Swift Types|Misc Swift Types]]
- [[_COMMUNITY_Changelog|Changelog]]
- [[_COMMUNITY_slider_math.dart|slider_math.dart]]
- [[_COMMUNITY_history_screen.dart|history_screen.dart]]
- [[_COMMUNITY_How to join (Android)|How to join (Android)]]
- [[_COMMUNITY_big_time_display.dart|big_time_display.dart]]
- [[_COMMUNITY_packagefluttermaterial.dart|package:flutter/material.dart]]
- [[_COMMUNITY_dartmath|dart:math]]
- [[_COMMUNITY_TimerNotifier|TimerNotifier]]
- [[_COMMUNITY_CLAUDE|CLAUDE.md]]
- [[_COMMUNITY_record Package (mic PCM capture)|record Package (mic PCM capture)]]
- [[_COMMUNITY_Auto-Configure Sensitivity and Frequency Band (v1.2.0-1.4.1)|Auto-Configure Sensitivity and Frequency Band (v1.2.0-1.4.1)]]
- [[_COMMUNITY_Feature Keep Tracking While in Background (v1.3.0)|Feature: Keep Tracking While in Background (v1.3.0)]]
- [[_COMMUNITY_Fix Notch Out Beep Tone So Shots Register During It (v1.2.0)|Fix: Notch Out Beep Tone So Shots Register During It (v1.2.0)]]
- [[_COMMUNITY_Release History (CHANGELOG)|Release History (CHANGELOG)]]
- [[_COMMUNITY_Closed Testing Program on Google Play|Closed Testing Program on Google Play]]
- [[_COMMUNITY_audioplayers Package (beep playback)|audioplayers Package (beep playback)]]
- [[_COMMUNITY_flutter_foreground_task Package (keep app alive while timer runs)|flutter_foreground_task Package (keep app alive while timer runs)]]
- [[_COMMUNITY_flutter_riverpod Package (state management)|flutter_riverpod Package (state management)]]
- [[_COMMUNITY_shared_preferences Package (settings persistence)|shared_preferences Package (settings persistence)]]
- [[_COMMUNITY_sqflite Package (local SQLite persistence)|sqflite Package (local SQLite persistence)]]
- [[_COMMUNITY_Beep Playback (audioplayers, in-memory sine-wave WAV)|Beep Playback (audioplayers, in-memory sine-wave WAV)]]
- [[_COMMUNITY_AudioContext audioFocusnone So Beep Does Not Pause AudioRecord|AudioContext audioFocus:none So Beep Does Not Pause AudioRecord]]
- [[_COMMUNITY_Beep Blanking Window (start beep + acoustic decay never registers as shot)|Beep Blanking Window (start beep + acoustic decay never registers as shot)]]
- [[_COMMUNITY_Drill Modes (Standard  Par  Stage)|Drill Modes (Standard / Par / Stage)]]
- [[_COMMUNITY_JSON-Backed Runtime Localization (flat dot-notation keys, key fallback)|JSON-Backed Runtime Localization (flat dot-notation keys, key fallback)]]
- [[_COMMUNITY_Persistence (sqflite stringsshots + shared_preferences settings)|Persistence (sqflite strings/shots + shared_preferences settings)]]
- [[_COMMUNITY_Shot Detection (PCM Mic Stream, Amplitude Peak Detection)|Shot Detection (PCM Mic Stream, Amplitude Peak Detection)]]
- [[_COMMUNITY_Riverpod State Management (single TimerNotifier owns Stopwatch, beeps, mic subscription)|Riverpod State Management (single TimerNotifier owns Stopwatch, beeps, mic subscription)]]
- [[_COMMUNITY_Monochrome Material 3 Theme (surfaceTint transparent to kill elevation hue bloom)|Monochrome Material 3 Theme (surfaceTint transparent to kill elevation hue bloom)]]
- [[_COMMUNITY_Semantic Versioning via Conventional Commits + release-please Release Flow|Semantic Versioning via Conventional Commits + release-please Release Flow]]

## God Nodes (most connected - your core abstractions)
1. `settingsProvider` - 16 edges
2. `databaseProvider` - 15 edges
3. `shotDetectorProvider` - 14 edges
4. `Simple Shot Timer` - 13 edges
5. `SliderUnit` - 9 edges
6. `TimerNotifier` - 7 edges
7. `Changelog` - 7 edges
8. `AppDelegate` - 6 edges
9. `DelayMode` - 6 edges
10. `DrillMode` - 6 edges

## Surprising Connections (you probably didn't know these)
- `GitHub Sponsors Funding (Mr-Jami)` --conceptually_related_to--> `Simple Shot Timer`  [INFERRED]
  .github/FUNDING.yml → README.md
- `CI Workflow: Analyze & Test Job` --references--> `Analyzer / Lint Configuration (flutter_lints + prefer_single_quotes)`  [INFERRED]
  .github/workflows/ci.yml → analysis_options.yaml
- `CI Workflow: Analyze & Test Job` --references--> `simple_shot_timer Package Manifest (pubspec.yaml, v1.4.1+6)`  [INFERRED]
  .github/workflows/ci.yml → pubspec.yaml
- `Deploy to Google Play Job (Build & Publish AAB)` --references--> `simple_shot_timer Package Manifest (pubspec.yaml, v1.4.1+6)`  [EXTRACTED]
  .github/workflows/deploy-play-store.yml → pubspec.yaml
- `Analyzer / Lint Configuration (flutter_lints + prefer_single_quotes)` --references--> `flutter_lints Dev Dependency`  [EXTRACTED]
  analysis_options.yaml → pubspec.yaml

## Import Cycles
- None detected.

## Communities (80 total, 27 thin omitted)

### Community 0 - "Audio Capture & Shot Detection"
Cohesion: 0.03
Nodes (63): audio_service.dart, AudioRecorder, beep_onset_detector.dart, biquad.dart, Float64List, ios_audio_session.dart, armBeepDetection, _assumedDeliveryDelayMs (+55 more)

### Community 1 - "App Bootstrap & Providers"
Cohesion: 0.04
Nodes (46): app.dart, audio, db, main, prefs, detector, sharedPreferencesProvider, AudioService (+38 more)

### Community 2 - "App Settings Model"
Cohesion: 0.05
Nodes (36): audioLatencyOffsetMaxMs, audioLatencyOffsetMinMs, audioLatencyOffsetMs, bandFilterEnabled, bandHighHz, bandHighMaxHz, bandHighMinHz, bandLowHz (+28 more)

### Community 3 - "History Screen"
Cohesion: 0.09
Nodes (23): IconData, stringByIdProvider, build, _buildShotRows, _ChipSpec, createState, cycle, _cycleOrdinal (+15 more)

### Community 4 - "Localization (i18n)"
Cohesion: 0.05
Nodes (39): BuildContext, class, AppLocale, AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsX, code, delegate (+31 more)

### Community 5 - "Timer Provider Core"
Cohesion: 0.06
Nodes (34): addManualShot, _awaitingOnset, _beepOnsetSub, _beepTimer, _beginCycle, build, _clock, computeDelay (+26 more)

### Community 6 - "CI/CD & Release Automation"
Cohesion: 0.25
Nodes (8): CI Workflow: Analyze & Test Job, Deploy to Google Play Job (Build & Publish AAB), Play Store Release Notes from GitHub Release Body, Monotonic versionCode via github.run_number, Release Please Workflow (release PR automation), Analyzer / Lint Configuration (flutter_lints + prefer_single_quotes), flutter_lints Dev Dependency, simple_shot_timer Package Manifest (pubspec.yaml, v1.4.1+6)

### Community 7 - "FFT Utilities"
Cohesion: 0.06
Nodes (32): alpha, beta, binHz, cum, dominantHz, fftRadix2, gamma, highBin (+24 more)

### Community 8 - "SQLite Database Service"
Cohesion: 0.07
Nodes (27): dart:io, Database, close, countStrings, _createSchema, _db, deleteAll, deleteString (+19 more)

### Community 9 - "Auto-Configure Analysis"
Cohesion: 0.06
Nodes (35): AppSettings, settingsServiceProvider, build, reset, SettingsNotifier, update, bandHighHz, bandHighHzRaw (+27 more)

### Community 10 - "iOS Runner (Swift)"
Cohesion: 0.08
Nodes (20): Any, AVAudioSession, AVFoundation, Bool, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate (+12 more)

### Community 11 - "Par Config Model"
Cohesion: 0.08
Nodes (23): dart:convert, double get, int?, copyWith, decodeList, durationMs, durationSeconds, enabled (+15 more)

### Community 12 - "Timer String Model"
Cohesion: 0.08
Nodes (23): copyWith, createdAt, delayMode, delayUsedMs, drillMode, firstShotForCycle, firstShotMs, fromMap (+15 more)

### Community 13 - "Settings Screen Widgets"
Cohesion: 0.05
Nodes (46): auto_configure_screen.dart, EdgeInsetsGeometry?, ../i18n/app_localizations.dart, AppThemeMode, AppThemeModeX, DelayMode, DelayModeX, DrillMode (+38 more)

### Community 14 - "Screen Theming & State Display"
Cohesion: 0.10
Nodes (19): Brightness, history_screen.dart, brightness, _delayLabel, firstShotMs, _invertMatrix, label, _parLabel (+11 more)

### Community 15 - "Auto-Configure Screen"
Cohesion: 0.05
Nodes (36): AudioPlayer, dart:async, build, createState, _error, _formatHz, label, onApply (+28 more)

### Community 16 - "Timer State Model"
Cohesion: 0.10
Nodes (19): int get, copyWith, currentCycleShotCount, currentCycleShots, currentParIndex, delayUsedMs, elapsedMs, error (+11 more)

### Community 17 - "Home Screen Widgets"
Cohesion: 0.12
Nodes (17): _ShotList, _SuggestionCard, _SuggestionRow, _AppBarLogo, _CountdownView, _IdleView, _SettingsSummary, _Stat (+9 more)

### Community 18 - "Mic Test Screen"
Cohesion: 0.11
Nodes (17): DateTime, double?, createState, _dominantFreqHz, _dominantFreqStrength, _error, freqHz, _FrequencyReadout (+9 more)

### Community 19 - "Flash Overlay Widget"
Cohesion: 0.13
Nodes (15): AnimationController, build, child, createState, _ctrl, didUpdateWidget, dispose, enabled (+7 more)

### Community 20 - "History Provider"
Cohesion: 0.12
Nodes (19): AsyncNotifier, build, delete, deleteAll, HistoryNotifier, refresh, databaseProvider, read (+11 more)

### Community 21 - "App Root & Controls"
Cohesion: 0.21
Nodes (15): ConsumerWidget, build, SimpleShotTimerApp, settingsProvider, timerProvider, _apply, build, _ControlsRow (+7 more)

### Community 22 - "Beep Onset Detector Tests"
Cohesion: 0.13
Nodes (14): package:simple_shot_timer/services/beep_onset_detector.dart, attackSamples, _beepHz, _concat, _findOnset, main, _make, null (+6 more)

### Community 23 - "Background Service"
Cohesion: 0.13
Nodes (14): @pragma, BackgroundService, _emptyTaskCallback, init, _initialized, _NoopTaskHandler, onDestroy, onRepeatEvent (+6 more)

### Community 24 - "Beep Onset Detector"
Cohesion: 0.13
Nodes (14): absoluteThreshold, BeepOnsetDetector, _blockPower, blockSize, _coeff, _floor, floorAttack, process (+6 more)

### Community 25 - "Delay Test Suite"
Cohesion: 0.17
Nodes (9): package:flutter_test/flutter_test.dart, package:simple_shot_timer/models/app_settings.dart, package:simple_shot_timer/models/par_schedule.dart, package:simple_shot_timer/utils/slider_math.dart, package:simple_shot_timer/utils/slider_units.dart, main, main, main (+1 more)

### Community 26 - "Auto-Configure Screen State"
Cohesion: 0.32
Nodes (8): ConsumerState, ConsumerStatefulWidget, AutoConfigureScreen, _AutoConfigureScreenState, MicTestScreen, _MicTestScreenState, _ReviewBody, _ReviewBodyState

### Community 27 - "Par Schedule Model"
Cohesion: 0.22
Nodes (8): app_settings.dart, enums.dart, computeParSchedule, cycle, kind, ParBeepEvent, ParBeepKind, timeMs

### Community 28 - "Settings Provider"
Cohesion: 0.11
Nodes (18): GitHub Sponsors Funding (Mr-Jami), Adding a New Language, Architecture Notes, Commit format, Continuous Integration, Features, Getting Started, License (+10 more)

### Community 29 - "Timer Run Lifecycle"
Cohesion: 0.18
Nodes (11): shotDetectorProvider, _armOnsetDetection, _cleanup, start, _startTick, _teardownRun, dispose, _start (+3 more)

### Community 30 - "Release Please Config"
Cohesion: 0.22
Nodes (8): changelog-path, changelog-sections, include-component-in-tag, include-v-in-tag, package-name, packages, release-type, $schema

### Community 31 - "Monochrome Theme"
Cohesion: 0.29
Nodes (6): _buildTheme, _monochromeScheme, ../models/enums.dart, package:flutter_localizations/flutter_localizations.dart, ../providers/settings_provider.dart, screens/home_screen.dart

### Community 32 - "Biquad Filters"
Cohesion: 0.25
Nodes (7): Biquad, highpass, lowpass, notch, processInt16InPlace, reset, _x1

### Community 33 - "Auto-Configure Tests"
Cohesion: 0.29
Nodes (6): dart:typed_data, package:simple_shot_timer/models/calibration_shot.dart, package:simple_shot_timer/services/auto_configure.dart, package:simple_shot_timer/utils/fft.dart, main, shot

### Community 34 - "Biquad Filter Tests"
Cohesion: 0.29
Nodes (6): package:simple_shot_timer/services/biquad.dart, beepHz, main, peakAbs, sampleRate, sine

### Community 35 - "Android Plugin Registrant"
Cohesion: 0.47
Nodes (4): GeneratedPluginRegistrant, String, FlutterEngine, Keep

### Community 36 - "iOS LLDB Debug Helper"
Cohesion: 0.33
Nodes (5): handle_new_rx_page(), __lldb_init_module(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., SBDebugger, SBFrame

### Community 37 - "Calibration Shot Model"
Cohesion: 0.33
Nodes (5): CalibrationShot, dominantHz, highEdgeHz, lowEdgeHz, peakAmplitude

### Community 38 - "Time Formatting Utils"
Cohesion: 0.33
Nodes (5): formatClock, formatSeconds, formatSplit, seconds, toStringAsFixed

### Community 39 - "App Branding Icon"
Cohesion: 0.60
Nodes (5): Simple Shot Timer App Icon (branding master), Monochrome Flat Line-Art Icon Style (single-color glyph on transparent background), Tapering Motion/Speed Lines Motif, Open Circular Arc Motif (timer dial / sound wave), Shot Timer (shooting-sports timing) Concept

### Community 40 - "String Provider"
Cohesion: 0.16
Nodes (17): bool get, CountUnit, editText, format, FractionPercentUnit, fromNumber, HertzUnit, isDecimal (+9 more)

### Community 41 - "Split Time Tests"
Cohesion: 0.33
Nodes (5): package:simple_shot_timer/models/enums.dart, package:simple_shot_timer/models/shot.dart, package:simple_shot_timer/models/timer_string.dart, main, _string

### Community 50 - "Changelog"
Cohesion: 0.12
Nodes (16): [1.1.0](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.0.0...v1.1.0) (2026-05-15), [1.2.0](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.1.0...v1.2.0) (2026-05-19), [1.3.0](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.2.0...v1.3.0) (2026-05-20), [1.4.0](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.3.0...v1.4.0) (2026-05-20), [1.4.1](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.4.0...v1.4.1) (2026-06-02), [1.5.0](https://github.com/Mr-Jami/simple-shot-timer/compare/v1.4.1...v1.5.0) (2026-07-05), Bug Fixes, Bug Fixes (+8 more)

### Community 51 - "slider_math.dart"
Cohesion: 0.18
Nodes (10): clamp, clampToStep, clampToStepDouble, nearest, snapped, softSnap, stepped, tolerance (+2 more)

### Community 52 - "history_screen.dart"
Cohesion: 0.22
Nodes (9): historyProvider, build, _drillSummary, fmt, HistoryScreen, package:intl/intl.dart, ../providers/history_provider.dart, review_screen.dart (+1 more)

### Community 53 - "How to join (Android)"
Cohesion: 0.25
Nodes (7): 1. Join the tester group, 2. Opt in to the test, 3. Install, How to join (Android), Join the closed test for Simple Shot Timer, Leaving the test, Reporting bugs and feedback

### Community 54 - "big_time_display.dart"
Cohesion: 0.29
Nodes (6): BigTimeDisplay, build, fontSize, label, timeMs, ../utils/time_format.dart

### Community 55 - "package:flutter/material.dart"
Cohesion: 0.29
Nodes (6): build, height, level, MicLevelMeter, threshold, package:flutter/material.dart

### Community 56 - "dart:math"
Cohesion: 0.33
Nodes (4): dart:math, package:simple_shot_timer/providers/timer_provider.dart, main, main

### Community 57 - "TimerNotifier"
Cohesion: 0.33
Nodes (6): TimerState, audioServiceProvider, _playParBeep, _playStartBeep, TimerNotifier, build

## Ambiguous Edges - Review These
- `Open Circular Arc Motif (timer dial / sound wave)` → `Shot Timer (shooting-sports timing) Concept`  [AMBIGUOUS]
  assets/branding/icon.png · relation: conceptually_related_to

## Knowledge Gaps
- **568 isolated node(s):** `flutter_export_environment.sh script`, `XCTest`, `AVFoundation`, `+registerWithRegistry`, `_buildTheme` (+563 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Open Circular Arc Motif (timer dial / sound wave)` and `Shot Timer (shooting-sports timing) Concept`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `DelayMode` connect `Settings Screen Widgets` to `App Settings Model`, `Timer String Model`, `Timer Provider Core`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Why does `DrillMode` connect `Settings Screen Widgets` to `App Settings Model`, `Timer String Model`, `Timer Provider Core`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Why does `AppSettings` connect `Auto-Configure Analysis` to `App Settings Model`, `Timer Provider Core`, `Screen Theming & State Display`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **What connects `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `flutter_export_environment.sh script`, `XCTest` to the rest of the system?**
  _573 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Audio Capture & Shot Detection` be split into smaller, more focused modules?**
  _Cohesion score 0.03125 - nodes in this community are weakly interconnected._
- **Should `App Bootstrap & Providers` be split into smaller, more focused modules?**
  _Cohesion score 0.04421768707482993 - nodes in this community are weakly interconnected._