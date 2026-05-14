# Simple Shot Timer

A simple shot timer built with Flutter.

> Status: project scaffold only. Application code has not been implemented yet.

## Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `>=3.19.0` (CI pins `3.41.9`)
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

Platform folders (`android/`, `ios/`) are generated. To regenerate (e.g. add `web`, `windows`):

```bash
flutter create . --platforms=android,ios,web
```

## Project Structure

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                  # Lint + test on every push / PR
│       └── deploy-play-store.yml   # Build AAB and publish to Google Play
├── lib/
│   └── main.dart                   # App entry point (placeholder)
├── test/
│   └── widget_test.dart            # Placeholder test
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## Continuous Integration

`.github/workflows/ci.yml` runs on every push and PR against `main`:

- `dart format` check
- `flutter analyze`
- `flutter test`

## Releasing to Google Play

`.github/workflows/deploy-play-store.yml` builds a signed Android App Bundle and uploads it to Google Play.

### Triggers

- **Tag push** matching `v*.*.*` (e.g. `v1.0.0`) — publishes to the `internal` track.
- **Manual** via the *Run workflow* button — you choose the track (`internal`, `alpha`, `beta`, `production`).

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

1. Confirm the Android `applicationId` (currently `com.simpleshottimer.simple_shot_timer` in `android/app/build.gradle.kts`) matches what you'll register in Play Console. Update `PACKAGE_NAME` in `.github/workflows/deploy-play-store.yml` if you change it.
2. Create your first release in the Play Console manually — the API cannot create the initial app listing.
3. Generate an upload keystore:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```
4. Wire the keystore into `android/app/build.gradle.kts` (the workflow writes `android/key.properties` from secrets at build time).
5. Create a service account in Google Cloud, grant it access in the Play Console, and download its JSON key.
6. Add all five secrets listed above to GitHub.
7. Tag a release: `git tag v1.0.0 && git push --tags`.

## License

TBD.
