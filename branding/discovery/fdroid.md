# F-Droid

Checked 2026-10-19 against app 2.3.1. Draft metadata: [cc.jami.simpleshottimer.yml](cc.jami.simpleshottimer.yml).

## Verdict

Simple Shot Timer can go into the main F-Droid repository as it is, and no
anti-feature should apply. There was one practical blocker: the release
build signed itself with the debug key. It is now fixed in this repository,
and `v2.3.1` needs one `sed` line in the recipe.

## What was checked

**License.** GPL-3.0-only. The [Inclusion Policy](https://f-droid.org/en/docs/Inclusion_Policy/)
asks for free software and for assets with a valid license that allows
redistribution. The additional terms in [NOTICE](../../NOTICE) are the ones
GPLv3 section 7 allows:
- attribution (7(b))
- marking modified versions (7(c))
- no trademark rights to the name, icon and logo (7(e))

F-Droid builds the unmodified source and only signs it, so the build may
carry the original name and icon.

The icon's copyright license is the repository's GPL; only trademark rights
are reserved. The [Non-Free Assets](https://f-droid.org/en/docs/Anti-Features/)
anti-feature is meant for artwork under non-commercial or no-derivatives
licenses, so it does not fit. The policy also says apps need the trademark
permissions they use. Say in the merge request that you, the trademark
holder, submit the app and allow F-Droid to distribute it under its name and
icon.

**Dependencies.** I ran
`gradlew :app:dependencies --configuration releaseRuntimeClasspath` (Flutter
3.41.9). The release runtime classpath contains only:
- AndroidX
- Kotlin and kotlinx
- Okio, Guava and ReLinker
- the Flutter engine artifacts

It has no `com.google.android.gms`, Firebase, Play Core
(`com.google.android.play`), billing, analytics or crash-reporting library.

The Flutter plugins are:
- audioplayers
- device_info_plus
- flutter_foreground_task
- jni and jni_flutter (pulled in by path_provider_android; they compile C
  code with the NDK)
- package_info_plus
- permission_handler
- record
- share_plus
- shared_preferences
- sqflite
- url_launcher
- vibration

The 118 locked pub packages contain no prebuilt `.so`, `.aar`, `.jar` or
`.dylib` files outside `example/` folders. The only exceptions are the
`gradle-wrapper.jar` files in jni and vibration. The usual
`scandelete: .pub-cache` removes them; the build doesn't use them.

**Permissions.** These are the permissions of the built APK (`aapt2 dump
permissions`):
- `RECORD_AUDIO`
- `WAKE_LOCK`
- `VIBRATE`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MICROPHONE`
- `POST_NOTIFICATIONS`

There is no `INTERNET` permission, so the app cannot talk to any server. The
Tracking and Non-Free Network anti-features can't apply. This is worth
saying in the merge request and the description.

**Signing.** F-Droid's [Build Metadata Reference](https://f-droid.org/en/docs/Build_Metadata_Reference/)
says `output` is "the resulting unsigned release APK"; F-Droid signs it with
its own key. `android/app/build.gradle.kts` used to fall back to the debug
key when `key.properties` was missing. Since `build(android): leave the
release APK unsigned without key.properties`, that build is unsigned.
- CI is unchanged: it writes `key.properties` and signs with the upload key.
- `flutter build apk --release` without the key now gives
  `build/app/outputs/apk/release/app-release-unsigned.apk`.
  `apksigner verify` says "DOES NOT VERIFY: Missing META-INF/MANIFEST.MF".
- For an installable local build, use `--debug` or `--profile`.
- Tags before that commit (`v2.3.1`) need the `sed` in the draft's `prebuild`.

**Version code.** F-Droid builds with `flutter build apk`, so the APK takes
the `+N` from `pubspec.yaml`: 2.3.1 is versionCode 14 (checked with `aapt2
dump badging`). The Play builds use `github.run_number`, which is higher.
That is fine because F-Droid and Play builds carry different signatures and
are separate installs anyway. Switching between them means uninstalling, and
the history is stored only on the phone. Users should export to CSV first.

**Toolchain.**
- Flutter `3.41.9`, as in CI. The tag exists: commit `00b0c91f06`.
- NDK `r28c`. That is 28.2.13676358, Flutter 3.41.9's default, needed
  because jni compiles C code.
- minSdk 24 (Android 7.0), targetSdk 36.
- `android/gradle.properties` keeps Flutter's default `-Xmx8G`. If F-Droid's
  builder runs out of memory, reviewers can lower it with a `sed` in
  `prebuild`.

**Store texts and images.** F-Droid reads
`fastlane/metadata/android/<locale>/` from the repository: title, short and
full description in eight languages, plus
`en-US/images/icon.png` (512x512), `featureGraphic.png` (1024x500),
`phoneScreenshots/1.png` to `8.png` (1080x1920, the Play screenshots) and
`changelogs/<versionCode>.txt`. The Play upload workflow skips images and
changelogs, so it is unaffected.

## How the recipe is built

It follows current fdroiddata Flutter recipes:
- **F-Droid's own Flutter srclib**, `srclibs: flutter@<tag>`, used as
  `$$flutter$$/bin/flutter`. fdroiddata has thousands of `flutter@` srclib
  uses, according to a
  [feasibility review that counted them](https://github.com/simonoppowa/opennutritracker/blob/8d2420f0305c96a4f798f3a111509827260f6df7/docs/fdroid-submission-feasibility.md).
- **A pub cache inside the build tree**, removed by `scandelete`.
- **`flutter pub get --enforce-lockfile`**.
- **A universal unsigned APK** from the Gradle output folder, like
  [Open Food Facts](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/openfoodfacts.github.scrachx.openfood.yml)
  (`output: build/app/outputs/apk/release/app-release-unsigned.apk`).
- **The `UpdateCheckData` pattern for `pubspec.yaml`** that
  [Saber](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.adilhanney.saber.yml)
  uses: `pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+`.

## Submitting

1. Merge the branch with the unsigned-release change, ideally before the
   next release PR. Then the next tag builds without the `sed`, and you can
   submit that version instead.
2. Create a GitLab account and fork
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata).
3. Copy `cc.jami.simpleshottimer.yml` from this folder to
   `metadata/cc.jami.simpleshottimer.yml` in the fork. To submit a newer
   version than 2.3.1:
   - update `versionName`, `versionCode`, `commit` (the tag's commit hash),
     `CurrentVersion` and `CurrentVersionCode`
   - remove the `sed` line
4. Optional local check with fdroidserver on Linux, WSL or the
   [fdroidserver Docker image](https://gitlab.com/fdroid/docker-executable-fdroidserver):
   `fdroid readmeta`, `fdroid rewritemeta cc.jami.simpleshottimer`,
   `fdroid lint cc.jami.simpleshottimer`,
   `fdroid build -v -l cc.jami.simpleshottimer`. You can skip this, because
   the merge request pipeline runs lint and a build too.
5. Open a merge request, "New app: Simple Shot Timer", with the template.
   Mention three things:
   - you are the developer and trademark holder, and allow distribution
     under the name and icon
   - the app has no `INTERNET` permission
   - the release build is unsigned without `key.properties`
6. Answer the reviewers. Once merged, the app appears after F-Droid's next
   build and index cycle, usually within days.

The slower alternative is a
[Request For Packaging](https://gitlab.com/fdroid/rfp/-/issues) issue, where
volunteers write the recipe. See also the
[Quick Start Guide](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/).

## On every release

- **Nothing changes in the normal flow.** release-please tags `vX.Y.Z` and
  bumps `+N` in `pubspec.yaml`. F-Droid's update checker finds the tag
  (`UpdateCheckMode: Tags` plus `UpdateCheckData`), and
  `AutoUpdateMode: Version` adds a build entry by itself. The F-Droid build
  follows in its next cycle.
- **Flutter version bumps.** The new entry is a copy of the last one,
  including `flutter@3.41.9`. When CI moves to a new Flutter version, send a
  small fdroiddata merge request that bumps the srclib, or the F-Droid build
  may fail.
- **"What's new" text (optional).** Add
  `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt`. Without
  it, F-Droid links to the changelog. It could be generated in CI with
  `.github/scripts/play_release_notes.py`, like the Play notes.
- **Screenshots.** Refresh `images/phoneScreenshots` when the UI changes,
  from `branding/store-listing/out/`.

## IzzyOnDroid, the faster route

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/info) is an F-Droid
compatible repository. It takes APKs straight from the developer's releases,
which it prefers, has its own
[App Inclusion Policy](https://izzyondroid.org/docs/general/AppInclusionPolicy/),
and usually lists an app within days. Requests go through
[its issue tracker](https://codeberg.org/IzzyOnDroid/repodata/issues).

The catch is that this project attaches no APKs to its GitHub Releases. That
would take a step in a workflow (for example `deploy-play-store.yml`) that:
- builds `flutter build apk --release` with `key.properties` (the upload key
  or a dedicated key)
- runs `gh release upload vX.Y.Z build/app/outputs/flutter-apk/app-release.apk`

That APK's signature would differ from both the Play and the F-Droid build.
Both repositories can list the app at the same time; the main F-Droid
repository reaches more people.
