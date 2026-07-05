# Graph Report - .  (2026-07-05)

## Corpus Check
- 126 files · ~134,615 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 839 nodes · 1067 edges · 50 communities (45 shown, 5 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 13 edges (avg confidence: 0.87)
- Token cost: 34,900 input · 6,393 output

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

## God Nodes (most connected - your core abstractions)
1. `settingsProvider` - 16 edges
2. `databaseProvider` - 15 edges
3. `shotDetectorProvider` - 14 edges
4. `Simple Shot Timer App` - 11 edges
5. `TimerNotifier` - 7 edges
6. `DelayMode` - 6 edges
7. `DrillMode` - 6 edges
8. `audioServiceProvider` - 6 edges
9. `_MicTestScreenState` - 6 edges
10. `Deploy to Google Play Job (Build & Publish AAB)` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Fix: Notch Out Beep Tone So Shots Register During It (v1.2.0)` --semantically_similar_to--> `Beep Blanking Window (start beep + acoustic decay never registers as shot)`  [INFERRED] [semantically similar]
  CHANGELOG.md → README.md
- `JSON-Backed Runtime Localization (flat dot-notation keys, key fallback)` --references--> `kSupportedAppLocales`  [EXTRACTED]
  README.md → lib/i18n/app_localizations.dart
- `GitHub Sponsors Funding (Mr-Jami)` --conceptually_related_to--> `Simple Shot Timer App`  [INFERRED]
  .github/FUNDING.yml → README.md
- `Closed Testing Program on Google Play` --shares_data_with--> `Deploy to Google Play Job (Build & Publish AAB)`  [INFERRED]
  JOIN_TESTING.md → .github/workflows/deploy-play-store.yml
- `CI Workflow: Analyze & Test Job` --references--> `Analyzer / Lint Configuration (flutter_lints + prefer_single_quotes)`  [INFERRED]
  .github/workflows/ci.yml → analysis_options.yaml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Release Automation Pipeline (conventional commits to Play Store)** — _github_workflows_ci_analyze_and_test, _github_workflows_release_please_workflow, _github_workflows_deploy_play_store_deploy, readme_versioning_release_flow, changelog_release_history, pubspec_simple_shot_timer [EXTRACTED 1.00]
- **Audio Capture and Beep Playback Pipeline** — readme_shot_detection, readme_audio_playback, readme_beep_blanking, readme_audiofocus_none, pubspec_record, pubspec_audioplayers [EXTRACTED 1.00]

## Communities (50 total, 5 thin omitted)

### Community 0 - "Audio Capture & Shot Detection"
Cohesion: 0.03
Nodes (61): audio_service.dart, AudioRecorder, beep_onset_detector.dart, biquad.dart, bool get, Float64List, armBeepDetection, _assumedDeliveryDelayMs (+53 more)

### Community 1 - "App Bootstrap & Providers"
Cohesion: 0.04
Nodes (46): app.dart, db, main, prefs, detector, service, sharedPreferencesProvider, AudioService (+38 more)

### Community 2 - "App Settings Model"
Cohesion: 0.05
Nodes (46): ../i18n/app_localizations.dart, audioLatencyOffsetMaxMs, audioLatencyOffsetMinMs, audioLatencyOffsetMs, bandFilterEnabled, bandHighHz, bandHighMaxHz, bandHighMinHz (+38 more)

### Community 3 - "History Screen"
Cohesion: 0.05
Nodes (44): IconData, historyProvider, stringByIdProvider, build, _drillSummary, fmt, HistoryScreen, build (+36 more)

### Community 4 - "Localization (i18n)"
Cohesion: 0.06
Nodes (37): AudioPlayer, BuildContext, class, AppLocale, AppLocalizations, _AppLocalizationsDelegate, AppLocalizationsX, code (+29 more)

### Community 5 - "Timer Provider Core"
Cohesion: 0.06
Nodes (34): addManualShot, _awaitingOnset, _beepOnsetSub, _beepTimer, _beginCycle, build, _clock, computeDelay (+26 more)

### Community 6 - "CI/CD & Release Automation"
Cohesion: 0.07
Nodes (33): GitHub Sponsors Funding (Mr-Jami), CI Workflow: Analyze & Test Job, Deploy to Google Play Job (Build & Publish AAB), Play Store Release Notes from GitHub Release Body, Monotonic versionCode via github.run_number, Release Please Workflow (release PR automation), Analyzer / Lint Configuration (flutter_lints + prefer_single_quotes), Auto-Configure Sensitivity and Frequency Band (v1.2.0-1.4.1) (+25 more)

### Community 7 - "FFT Utilities"
Cohesion: 0.06
Nodes (32): alpha, beta, binHz, cum, dominantHz, fftRadix2, gamma, highBin (+24 more)

### Community 8 - "SQLite Database Service"
Cohesion: 0.07
Nodes (27): dart:io, Database, close, countStrings, _createSchema, _db, deleteAll, deleteString (+19 more)

### Community 9 - "Auto-Configure Analysis"
Cohesion: 0.07
Nodes (28): bandHighHz, bandHighHzRaw, bandLowHz, byPeak, CalibrationSuggestion, consideredCount, freqs, isolateShotCluster (+20 more)

### Community 10 - "iOS Runner (Swift)"
Cohesion: 0.09
Nodes (17): Any, Bool, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterSceneDelegate, AppDelegate (+9 more)

### Community 11 - "Par Config Model"
Cohesion: 0.08
Nodes (23): dart:convert, double get, int?, copyWith, decodeList, durationMs, durationSeconds, enabled (+15 more)

### Community 12 - "Timer String Model"
Cohesion: 0.08
Nodes (23): copyWith, createdAt, delayMode, delayUsedMs, drillMode, firstShotForCycle, firstShotMs, fromMap (+15 more)

### Community 13 - "Settings Screen Widgets"
Cohesion: 0.09
Nodes (21): auto_configure_screen.dart, current, divisions, _formatHz, label, max, maxMs, min (+13 more)

### Community 14 - "Screen Theming & State Display"
Cohesion: 0.09
Nodes (21): Brightness, history_screen.dart, TimerState, TimerNotifier, brightness, _delayLabel, firstShotMs, _invertMatrix (+13 more)

### Community 15 - "Auto-Configure Screen"
Cohesion: 0.10
Nodes (20): build, createState, _error, _formatHz, label, onApply, onDiscard, _recomputeSuggestion (+12 more)

### Community 16 - "Timer State Model"
Cohesion: 0.10
Nodes (19): int get, copyWith, currentCycleShotCount, currentCycleShots, currentParIndex, delayUsedMs, elapsedMs, error (+11 more)

### Community 17 - "Home Screen Widgets"
Cohesion: 0.10
Nodes (20): _ShotList, _SuggestionCard, _AppBarLogo, _CountdownView, _IdleView, _SettingsSummary, _Stat, _StatsRow (+12 more)

### Community 18 - "Mic Test Screen"
Cohesion: 0.11
Nodes (17): dart:async, DateTime, double?, createState, _dominantFreqHz, _dominantFreqStrength, _error, freqHz (+9 more)

### Community 19 - "Flash Overlay Widget"
Cohesion: 0.13
Nodes (15): AnimationController, build, child, createState, _ctrl, didUpdateWidget, dispose, enabled (+7 more)

### Community 20 - "History Provider"
Cohesion: 0.16
Nodes (15): AsyncNotifier, build, delete, deleteAll, HistoryNotifier, refresh, databaseProvider, stop (+7 more)

### Community 21 - "App Root & Controls"
Cohesion: 0.19
Nodes (16): ConsumerWidget, SimpleShotTimerApp, settingsProvider, start, timerProvider, _apply, build, _ControlsRow (+8 more)

### Community 22 - "Beep Onset Detector Tests"
Cohesion: 0.12
Nodes (15): package:simple_shot_timer/services/beep_onset_detector.dart, return, attackSamples, _beepHz, _concat, _findOnset, main, _make (+7 more)

### Community 23 - "Background Service"
Cohesion: 0.13
Nodes (14): @pragma, BackgroundService, _emptyTaskCallback, init, _initialized, _NoopTaskHandler, onDestroy, onRepeatEvent (+6 more)

### Community 24 - "Beep Onset Detector"
Cohesion: 0.13
Nodes (14): absoluteThreshold, BeepOnsetDetector, _blockPower, blockSize, _coeff, _floor, floorAttack, process (+6 more)

### Community 25 - "Delay Test Suite"
Cohesion: 0.19
Nodes (10): dart:math, package:flutter_test/flutter_test.dart, package:simple_shot_timer/models/app_settings.dart, package:simple_shot_timer/models/enums.dart, package:simple_shot_timer/models/par_schedule.dart, package:simple_shot_timer/providers/timer_provider.dart, main, main (+2 more)

### Community 26 - "Auto-Configure Screen State"
Cohesion: 0.20
Nodes (12): ConsumerState, ConsumerStatefulWidget, audioServiceProvider, _playParBeep, _playStartBeep, AutoConfigureScreen, _AutoConfigureScreenState, build (+4 more)

### Community 27 - "Par Schedule Model"
Cohesion: 0.22
Nodes (8): app_settings.dart, enums.dart, computeParSchedule, cycle, kind, ParBeepEvent, ParBeepKind, timeMs

### Community 28 - "Settings Provider"
Cohesion: 0.31
Nodes (8): AppSettings, settingsServiceProvider, build, reset, SettingsNotifier, update, ../models/app_settings.dart, Notifier

### Community 29 - "Timer Run Lifecycle"
Cohesion: 0.22
Nodes (9): shotDetectorProvider, _armOnsetDetection, _cleanup, _startTick, _teardownRun, dispose, _start, _stop (+1 more)

### Community 30 - "Release Please Config"
Cohesion: 0.22
Nodes (8): changelog-path, changelog-sections, include-component-in-tag, include-v-in-tag, package-name, packages, release-type, $schema

### Community 31 - "Monochrome Theme"
Cohesion: 0.25
Nodes (7): build, _buildTheme, _monochromeScheme, ../models/enums.dart, package:flutter_localizations/flutter_localizations.dart, ../providers/settings_provider.dart, screens/home_screen.dart

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
Cohesion: 0.40
Nodes (4): read, ../models/timer_string.dart, package:flutter_riverpod/flutter_riverpod.dart, providers.dart

### Community 41 - "Split Time Tests"
Cohesion: 0.40
Nodes (4): package:simple_shot_timer/models/shot.dart, package:simple_shot_timer/models/timer_string.dart, main, _string

## Ambiguous Edges - Review These
- `Open Circular Arc Motif (timer dial / sound wave)` → `Shot Timer (shooting-sports timing) Concept`  [AMBIGUOUS]
  assets/branding/icon.png · relation: conceptually_related_to

## Knowledge Gaps
- **485 isolated node(s):** `flutter_export_environment.sh script`, `XCTest`, `+registerWithRegistry`, `_buildTheme`, `_monochromeScheme` (+480 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Open Circular Arc Motif (timer dial / sound wave)` and `Shot Timer (shooting-sports timing) Concept`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `kSupportedAppLocales` connect `CI/CD & Release Automation` to `Localization (i18n)`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **What connects `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `flutter_export_environment.sh script`, `XCTest` to the rest of the system?**
  _489 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Audio Capture & Shot Detection` be split into smaller, more focused modules?**
  _Cohesion score 0.03225806451612903 - nodes in this community are weakly interconnected._
- **Should `App Bootstrap & Providers` be split into smaller, more focused modules?**
  _Cohesion score 0.04336734693877551 - nodes in this community are weakly interconnected._
- **Should `App Settings Model` be split into smaller, more focused modules?**
  _Cohesion score 0.04609929078014184 - nodes in this community are weakly interconnected._
- **Should `History Screen` be split into smaller, more focused modules?**
  _Cohesion score 0.047872340425531915 - nodes in this community are weakly interconnected._