# Simple Shot Timer

A Flutter shot timer for dry-fire and live-fire drills. Detects shots through
the microphone, supports standard, par and stage drills, saves the drills you
run often, persists every string to local SQLite, and exports to CSV.

Available on [Google Play](https://play.google.com/store/apps/details?id=cc.jami.simpleshottimer).

## Features

- **Navigation** — Four tabs: Timer, Drills, History, Settings. The tab bar
  is greyed out and inert while a string is counting down or running.
- **Drill modes** — Standard (open string), Par (configurable repeat
  count with optional rest interval between cycles, each cycle bounded
  by distinct start/end beeps), and Stage (long single-window timer up
  to 200s for scenario practice).
- **Start delay** — Instant, fixed, or random within a min/max range.
- **Saved drills** — Save the current drill (mode, start delay, par/stage
  timing) under a name. On the Drills tab, tap a drill to apply it; its menu
  renames, overwrites or deletes it.
- **Shot detection** — Raw mic stream with the platform's voice processing
  bypassed, an optional frequency-band filter and a notch at the beep tone,
  then peak detection with an echo filter. The beep never counts as a shot,
  and a shot fired during the beep still does.
- **Auto-configure** — Fire a few shots and the app suggests a sensitivity
  and frequency band for that gun and range. You can still set both by hand.
- **Beep timing** — `t=0` is the moment the start beep is heard, measured
  through the mic, rather than the moment playback was requested. A manual
  latency offset covers output the mic can't hear, such as a Bluetooth
  speaker. The flash and haptic are delayed by the learned output latency so
  they land with the sound.
- **Live mic test** — Level meter with the threshold line to dial in
  sensitivity before going hot (Settings → Shot detection).
- **Background tracking** — A string keeps detecting shots and playing par
  beeps when you switch to another app.
- **History** — Every string saved automatically with a rolling cap (50–5000,
  default 500), together with the drill configuration it was shot with.
  Review individual strings with split times, fastest/slowest, average, and
  editable label / notes / penalty. A run that detects no shots is not saved
  unless you add a shot by hand.
- **CSV export** — Per-string or full-history export via the native share
  sheet.
- **Manual shots** — Add shots after the fact on the Timer tab; add or
  delete them in review.
- **Muted-phone notice** — While a string runs, a one-line notice appears
  if the media volume is muted or at zero. On Android, tapping it opens the
  volume panel.
- **Localization** — English, German, Spanish, French and Russian, with a
  JSON-backed delegate; adding a language means dropping one JSON file and
  adding one line.
- **Theme** — Monochrome Material 3 (matches the app icon). System / Light /
  Dark / High contrast selectable in settings.
- **Quality-of-life** — Visual screen flash on beep (an edge ring instead
  when the system asks for reduced motion), optional haptic on beep,
  keep-screen-awake during a string, portrait layout.

## Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>=3.19.0`
  (CI pins `3.41.9`)
- Dart SDK `>=3.3.0` (bundled with Flutter)
- JDK 17 (for Android builds)
- Android SDK with `platforms;android-36` + `build-tools;36.0.0` (or newer)

## Getting Started

```bash
# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run

# Static analysis & tests
flutter analyze
flutter test
```

Platform folders (`android/`, `ios/`) are generated and committed. To
regenerate or add a new platform:

```bash
flutter create . --platforms=android,ios,web
```

## Project Structure

```
.
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                  # Analyze + test on every push / PR
│   │   ├── release-please.yml      # Release PR, version bump, tag + GitHub Release
│   │   ├── deploy-play-store.yml   # Build AAB and publish to Google Play
│   │   └── deploy-app-store.yml    # Build IPA and upload to App Store Connect
│   ├── scripts/
│   │   └── play_release_notes.py   # GitHub Release body -> Play Store "What's new"
│   └── pull_request_template.md
├── android/                    # Android platform code (manifest, Gradle, volume channel)
├── ios/                        # iOS platform code (Xcode project, audio-session + volume channels)
├── assets/
│   ├── branding/               # App icon
│   └── i18n/                   # en, de, es, fr, ru translation bundles
├── branding/                   # Store-listing graphics + launch video sources (not bundled)
├── lib/
│   ├── app.dart                # MaterialApp wiring (theme, locale, delegates)
│   ├── main.dart               # Entry point: portrait lock, ProviderScope overrides
│   ├── i18n/                   # AppLocalizations + JSON-backed delegate
│   ├── models/                 # AppSettings, DrillConfig, CustomDrill, TimerString, par schedule, etc.
│   ├── providers/              # Riverpod notifiers (timer, settings, history, saved drills)
│   ├── screens/                # Tab shell, Timer, Drills, History, Review, Settings,
│   │                           # Shot detection, Mic test, Auto-configure
│   ├── services/               # Audio, shot + beep-onset detection, filters, SQLite,
│   │                           # CSV export, platform channels, timer ports
│   ├── theme/                  # Monochrome ThemeData
│   ├── utils/                  # FFT, slider math + units, motion, time formatting
│   └── widgets/                # BigTimeDisplay, FlashOverlay, MicLevelMeter, SettingsSlider, etc.
├── test/                       # Unit + widget tests, TimerNotifier runs under FakeAsync
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## Architecture Notes

- **State management** — [Riverpod](https://riverpod.dev) (`Notifier`s, no
  external state). The timer is a single `TimerNotifier` that owns the
  `Stopwatch`, beep timers, par schedule, and mic subscription. It reaches
  the platform only through four ports in `lib/services/timer_ports.dart`
  (`ShotSource`, `BeepPlayer`, `StringStore`, `RunEnvironment`), which the
  plugin-backed services implement. `test/timer_notifier_test.dart` drives
  whole runs against fakes under `FakeAsync`.
- **Persistence** — `sqflite` for strings/shots, `shared_preferences` for
  settings and saved drills (a JSON list). `SharedPreferences`, the database
  and `AudioService` are created once in `main()` and injected through
  `ProviderScope` overrides.
- **Audio** —
  - **Detection:** `record` package streams raw PCM16 chunks from the mic
    (`AudioSource.unprocessed` on Android, the `measurement` session mode on
    iOS, so voice processing doesn't flatten the shot transient).
    `ShotDetector` runs an optional band-pass and a notch at the beep
    frequency, then scans each chunk for the peak amplitude, applies an echo
    filter and a blanking window over the start delay, and emits a
    clock-relative timestamp.
  - **Beep onset:** before each start/par beep the detector arms a one-shot
    onset detector on the unfiltered signal. The timer anchors `t=0` to the
    audible onset and keeps a running estimate of the output latency
    (`beepLatencyEstimateMs`) that delays the flash and haptic.
  - **Playback:** `audioplayers` plays an in-memory sine-wave WAV. The
    Android `AudioContext` is configured with `audioFocus: none` and the
    media usage stream so the beep does not pause the active `AudioRecord`
    stream.
  - **Background:** during a string, `flutter_foreground_task` runs a
    microphone-type foreground service on Android, and iOS declares the
    `audio` background mode. Detection and beeps stay in the main isolate.
- **Platform channels** — `IosAudioSession` switches the iOS session mode,
  and `VolumeService` (`cc.jami.simpleshottimer/volume`) reports whether the
  media stream is audible and opens the volume panel. Both are handled in
  `MainActivity.kt` / `AppDelegate.swift`.
- **Internationalization** — Custom `LocalizationsDelegate` that loads
  `assets/i18n/{code}.json` at runtime. Lookups use a flat dot-notation key
  (`home.standBy`) with `{placeholder}` interpolation. Missing keys fall
  back to the key string itself, and `test/i18n_parity_test.dart` fails if
  any locale's keys or placeholders differ from `en.json`.
- **Theming** — Hand-tuned monochrome `ColorScheme` (pure black/white
  surfaces, neutral grey container variants, `surfaceTint: transparent`
  globally to kill M3's elevation-driven hue bloom). High contrast is its
  own palette. `test/theme_monochrome_test.dart` checks that every colour
  role stock widgets read stays grey.

## Adding a New Language

1. Copy `assets/i18n/en.json` to `assets/i18n/<code>.json` and translate the
   values (keep the keys identical).
2. Add one line to `kSupportedAppLocales` in
   `lib/i18n/app_localizations.dart`:

   ```dart
   AppLocale(code: 'it', displayName: 'Italiano'),
   ```

3. Run `flutter test`: `test/i18n_parity_test.dart` checks that the new file
   has every key and `{placeholder}` of `en.json`.

The Settings → Language dropdown picks the new option up automatically.

## Versioning

The project uses **semantic versioning** (`MAJOR.MINOR.PATCH`) driven by
**conventional commit** messages. Versions are bumped automatically by
[release-please](https://github.com/googleapis/release-please) — you never
edit `pubspec.yaml`'s version manually.

### Commit format

Each commit on `main` should start with a type:

| Commit prefix | Effect on next version | Example |
| --- | --- | --- |
| `feat:` | minor bump (`1.0.0` → `1.1.0`) | `feat: add German translation` |
| `fix:` | patch bump (`1.0.0` → `1.0.1`) | `fix: correct random delay countdown` |
| `feat!:` / `fix!:` / `BREAKING CHANGE:` footer | major bump (`1.0.0` → `2.0.0`) | `feat!: drop sqlite history schema v1` |
| `perf:` | patch bump | `perf: faster shot detection chunk loop` |
| `chore:`, `docs:`, `refactor:`, `test:`, `style:`, `ci:`, `build:` | no bump | `chore: update lints` |

A scope is optional: `feat(settings): add language picker`.

### Commit messages are store release notes

`feat:`, `fix:` and `perf:` subjects end up in two places:

- **GitHub Release / `CHANGELOG.md`**: verbatim, with scope, links and
  commit hashes.
- **Play Store "What's new"**: rewritten by
  `.github/scripts/play_release_notes.py` into plain bullets under
  *Changed*, *New*, *Fixes* and *Improvements*. Scope, links and issue
  numbers are removed, and the first letter is capitalised. Dependency
  bumps and reverts are left out, and the text is capped at 500 characters
  (later bullets are dropped first, with a warning in the deploy log).

A `BREAKING CHANGE:` footer is published in full under *Changed*, listed
first, so write it for users too: say what is gone or behaves differently.

So write the subject for the person updating the app, not for a reviewer.
Describe what changed for them in plain words:

| Instead of | Write |
| --- | --- |
| `fix(detector): notch out beep tone` | `fix(detector): shots fired during the beep are now detected` |
| `feat(ios): bypass voice DSP` | `feat(ios): cleaner shot detection on iPhone` |

Anything that users won't notice (refactors, tests, CI, build tweaks) should
use a non-releasing type such as `refactor:`, `test:`, `ci:` or `chore:` so
it stays out of the store notes. For squash-merged PRs, the **PR title**
becomes the commit subject, so the same rules apply to PR titles.

### Release flow

1. Land conventional commits on `main` via PR or direct push.
2. `.github/workflows/release-please.yml` opens (or updates) a single
   *Release PR* titled e.g. `chore(main): release 1.1.0`. The PR contains
   the version bump in `pubspec.yaml` and an updated `CHANGELOG.md`.
3. When you merge that PR, release-please creates a Git tag (`v1.1.0`) and
   a matching GitHub Release.
4. Start `.github/workflows/deploy-play-store.yml` from *Run workflow* in
   the Actions tab and pick the track. It builds the signed AAB from `main`
   and uploads it with notes taken from the latest GitHub Release.
   For iOS, start `.github/workflows/deploy-app-store.yml` the same way; the
   build lands in TestFlight and is submitted for review in App Store
   Connect.

> The Android `versionCode` and the iOS `CFBundleVersion` are set from
> `github.run_number` at build time, so they always increase monotonically
> (both stores require this even when the version name doesn't change).

> The tag from step 3 does not start the deploy by itself: release-please
> pushes it with the default `GITHUB_TOKEN`, which cannot trigger other
> workflows. To deploy on every release automatically, give release-please a
> Personal Access Token with `workflow` scope via its `token:` input; the tag
> push then publishes to the `internal` track.

## Continuous Integration

`.github/workflows/ci.yml` runs on every push and PR against `main`, on
Flutter `3.41.9` and JDK 17:

- `flutter analyze`
- `flutter test`

Formatting is not checked in CI.

## Releasing to Google Play

`.github/workflows/deploy-play-store.yml` builds a signed Android App
Bundle and uploads it to Google Play.

### Triggers

- **Tag push** matching `v*.*.*` (e.g. `v1.0.0`) — publishes to the
  `internal` track.
- **Manual** via the *Run workflow* button — choose the track (`internal`,
  `alpha`, `beta`, `production`).

### Required GitHub secrets

Configure these under *Settings → Secrets and variables → Actions*:

| Secret | Description |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Your upload keystore (`.jks`) encoded as base64. Generate with `base64 -w 0 upload-keystore.jks`. |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password. |
| `ANDROID_KEY_PASSWORD` | Key password (often the same as keystore password). |
| `ANDROID_KEY_ALIAS` | Key alias inside the keystore (e.g. `upload`). |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | JSON key for a Google Play service account with *Release manager* access. |

### One-time setup checklist

1. Confirm the Android `applicationId` (currently
   `cc.jami.simpleshottimer` in
   `android/app/build.gradle.kts`) matches what you'll register in Play
   Console. Update `PACKAGE_NAME` in `.github/workflows/deploy-play-store.yml`
   if you change it.
2. Create your first release in the Play Console manually — the API cannot
   create the initial app listing.
3. Generate an upload keystore:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```
4. Wire the keystore into `android/app/build.gradle.kts` (the workflow
   writes `android/key.properties` from secrets at build time).
5. Create a service account in Google Cloud, grant it access in the Play
   Console, and download its JSON key.
6. Add all five secrets listed above to GitHub.
7. Tag a release: `git tag v1.0.0 && git push --tags`.

## Releasing to the App Store

`.github/workflows/deploy-app-store.yml` builds a signed IPA on a macOS
runner with Xcode `26.3` and uploads it to App Store Connect, where it
appears in TestFlight. Submitting a build for App Review is done in App
Store Connect. The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

### Triggers

- **Tag push** matching `v*.*.*`.
- **Manual** via the *Run workflow* button.

### Required GitHub secrets

| Secret | Description |
| --- | --- |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Apple Distribution certificate with its private key as `.p12`, base64-encoded (`base64 -i distribution.p12`). |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password of that `.p12`. |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store provisioning profile for `cc.jami.simpleshottimer`, base64-encoded. The workflow reads the team ID and profile name from it. |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID of an App Store Connect team API key (*App Manager* role or higher). |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID shown above the key list in App Store Connect. |
| `APP_STORE_CONNECT_API_KEY` | Contents of the downloaded `AuthKey_<KEY_ID>.p8`. |

### One-time setup checklist

1. Have an active Apple Developer Program membership.
2. In App Store Connect, *Users and Access → Integrations → App Store
   Connect API*, create a team key and download its `.p8` (it can be
   downloaded only once).
3. In *Certificates, IDs & Profiles*, register the App ID
   `cc.jami.simpleshottimer` (no capabilities needed: background audio is
   an `Info.plist` entry), create an *Apple Distribution* certificate and an
   *App Store Connect* provisioning profile for that App ID.
4. Create the app in App Store Connect (*Apps → +*) with that bundle ID.
5. Add all six secrets listed above to GitHub.

The distribution certificate and the profile expire after one year; renew
both and update the three `IOS_*` secrets. Apple raises the minimum Xcode
for uploads every spring; bump `XCODE_VERSION` (and `runs-on` if the image
no longer has it) in the workflow when that happens.

## Permissions

Android:

- **`RECORD_AUDIO`** — required for shot detection through the mic. The app
  requests it the first time the mic is needed (START, mic test or
  auto-configure).
- **`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`** — keep detection
  and beeps running while the app is in the background during a string.
- **`POST_NOTIFICATIONS`** — Android 13+ needs it to show the foreground
  service's notification; requested when a string starts, if not yet
  granted.
- **`WAKE_LOCK`** — keeps the screen on during a string (toggleable in
  Settings).
- **`VIBRATE`** — optional haptic feedback on beep.

iOS:

- **`NSMicrophoneUsageDescription`** (`ios/Runner/Info.plist`) — the text
  of the microphone prompt. iOS closes an app that opens the mic without it.
- **`audio` background mode** — keeps detection and beeps running while the
  app is in the background during a string.

## Maintainer

Built and maintained by [Tareq Jami](https://tareqjami.de) of
[Jami IT](https://jami-it.de) — software engineering and AI consulting,
Hamburg, Germany. The app ships under `cc.jami.simpleshottimer` on
[Google Play](https://play.google.com/store/apps/details?id=cc.jami.simpleshottimer);
see [JOIN_TESTING.md](JOIN_TESTING.md) to get new builds early through the
beta. Bugs and feedback: [GitHub Issues](https://github.com/Mr-Jami/simple-shot-timer/issues).

## License

Simple Shot Timer is free software under the
[GNU General Public License v3.0](LICENSE), with additional terms under its
section 7 that are set out in [NOTICE](NOTICE). In short:

- You may use, study, modify and share the app, and you may sell modified
  versions, as long as you publish their full source code under the same
  license.
- Anything built on it must show this attribution in its legal notices
  (for example an About, Credits or Licenses screen):
  *"Based on Simple Shot Timer by Tareq Jami (Jami IT). The original app is
  free: https://github.com/Mr-Jami/simple-shot-timer"*
- Modified versions need their own name and must not present themselves as
  the original or as made or endorsed by Tareq Jami or Jami IT.

[NOTICE](NOTICE) is the binding text; this summary is for convenience.
Everything published before the switch to GPLv3, including all releases up
to 2.0.0, was licensed under the Apache License 2.0 and stays available
under it.
