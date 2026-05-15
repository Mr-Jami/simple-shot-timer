# Simple Shot Timer

A Flutter shot timer for dry-fire and live-fire drills. Detects shots through
the microphone, supports standard and par drills, persists every string to
local SQLite, and exports to CSV.

## Features

- **Drill modes** — Standard (open string), Par (configurable repeat
  count with optional rest interval between cycles, each cycle bounded
  by distinct start/end beeps), and Stage (long single-window timer up
  to 200s for scenario practice).
- **Start delay** — Instant, fixed, or random within a min/max range.
- **Shot detection** — Live PCM mic stream, amplitude-based peak detection
  with echo filter and beep blanking so the start/par beep never registers
  as a shot.
- **Live mic test** — Dedicated screen with a level meter and threshold line
  to dial in sensitivity before going hot.
- **History** — Every string saved automatically with a rolling cap (50–5000,
  default 500). Review individual strings with split times, fastest/slowest,
  average, and editable label / notes / penalty.
- **CSV export** — Per-string or full-history export via the native share
  sheet.
- **Manual shots** — Add or remove shots after the fact on the home screen
  or in review.
- **Localization** — English and German, with a JSON-backed delegate; adding
  a language means dropping one JSON file and adding one line.
- **Theme** — Monochrome Material 3 (matches the app icon). System / Light /
  Dark / High-contrast selectable in settings.
- **Quality-of-life** — Visual screen flash on beep, optional haptic on
  beep, keep-screen-awake during a string.

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
├── .github/workflows/
│   ├── ci.yml                  # Lint + test on every push / PR
│   └── deploy-play-store.yml   # Build AAB and publish to Google Play
├── android/                    # Android platform code (manifest, mipmaps, Gradle)
├── ios/                        # iOS platform code (Xcode project, AppIcon set)
├── assets/
│   └── i18n/                   # en.json, de.json — translation bundles
├── branding/                   # Store-listing artwork (not bundled at runtime)
├── lib/
│   ├── app.dart                # MaterialApp wiring (theme, locale, delegates)
│   ├── main.dart               # Entry point + ProviderScope bootstrap
│   ├── i18n/                   # AppLocalizations + JSON-backed delegate
│   ├── models/                 # AppSettings, Shot, TimerString, enums, etc.
│   ├── providers/              # Riverpod notifiers (timer, settings, history)
│   ├── screens/                # Home, Settings, History, Review, Mic Test
│   ├── services/               # Audio, mic detection, SQLite, CSV export
│   ├── utils/                  # time_format helpers
│   └── widgets/                # BigTimeDisplay, FlashOverlay, MicLevelMeter
├── test/                       # Unit tests for delay, detector, splits
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## Architecture Notes

- **State management** — [Riverpod](https://riverpod.dev) (`Notifier`s, no
  external state). The timer is a single `TimerNotifier` that owns the
  `Stopwatch`, beep timers, par schedule, and mic subscription.
- **Persistence** — `sqflite` for strings/shots, `shared_preferences` for
  settings. Settings are loaded once at startup via a provider override in
  `main.dart`.
- **Audio** —
  - **Detection:** `record` package streams PCM16 chunks from the mic.
    `ShotDetector` scans each chunk for the peak amplitude, applies an echo
    filter and a blanking window that covers the start beep + acoustic decay,
    then emits a clock-relative timestamp.
  - **Playback:** `audioplayers` plays an in-memory sine-wave WAV. The
    Android `AudioContext` is configured with `audioFocus: none` and the
    media usage stream so the beep does not pause the active `AudioRecord`
    stream.
- **Internationalization** — Custom `LocalizationsDelegate` that loads
  `assets/i18n/{code}.json` at runtime. Lookups use a flat dot-notation key
  (`home.standBy`) with `{placeholder}` interpolation. Missing keys fall
  back to the key string itself for visible-during-dev debugging.
- **Theming** — Hand-tuned monochrome `ColorScheme` (pure black/white
  surfaces, neutral grey container variants, `surfaceTint: transparent`
  globally to kill M3's elevation-driven hue bloom).

## Adding a New Language

1. Copy `assets/i18n/en.json` to `assets/i18n/<code>.json` and translate the
   values (keep the keys identical).
2. Add one line to `kSupportedAppLocales` in
   `lib/i18n/app_localizations.dart`:

   ```dart
   AppLocale(code: 'fr', displayName: 'Français'),
   ```

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

### Release flow

1. Land conventional commits on `main` via PR or direct push.
2. `.github/workflows/release-please.yml` opens (or updates) a single
   *Release PR* titled e.g. `chore(main): release 1.1.0`. The PR contains
   the version bump in `pubspec.yaml` and an updated `CHANGELOG.md`.
3. When you merge that PR, release-please creates a Git tag (`v1.1.0`) and
   a matching GitHub Release.
4. The tag push triggers `.github/workflows/deploy-play-store.yml`, which
   builds the signed AAB and uploads it to the Play Store `internal` track.

> The Android `versionCode` is set from `github.run_number` at build time,
> so it always increases monotonically (Play Store requires this even when
> the `versionName` doesn't change).

> If you want the release-please-created tag to also trigger the deploy
> workflow automatically, give release-please a Personal Access Token with
> `workflow` scope and pass it via the `token:` input — the default
> `GITHUB_TOKEN` cannot trigger other workflows. Otherwise you can kick
> the deploy off manually via *Run workflow* in the Actions tab.

## Continuous Integration

`.github/workflows/ci.yml` runs on every push and PR against `main`:

- `dart format` check
- `flutter analyze`
- `flutter test`

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

## Permissions

- **`RECORD_AUDIO`** — required for shot detection through the mic. The app
  requests it on first START.
- **`WAKE_LOCK`** — keeps the screen on during a string (toggleable in
  Settings).
- **`VIBRATE`** — optional haptic feedback on beep.

## License

See [LICENSE](LICENSE).
