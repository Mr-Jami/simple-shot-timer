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

**Version code.** F-Droid builds one APK per ABI with `flutter build apk
--split-per-abi`. Flutter sets each split's versionCode to ABI code × 1000
plus the `+N` from `pubspec.yaml`. The ABI codes are 1 for armeabi-v7a, 2
for arm64-v8a and 4 for x86_64, so 2.3.2 (`+15`) gives 1015, 2015 and
4015. The recipe's `VercodeOperation` (`%c + 1000`, `%c + 2000`,
`%c + 4000`) uses the same scheme, so `+N` has to stay below 1000. The
Play builds use `github.run_number` instead. That is fine because F-Droid
and Play builds carry different signatures and are separate installs
anyway. Switching between them means uninstalling, and the history is
stored only on the phone, so users should export to CSV first.

**Toolchain.**
- Flutter: the recipe reads `FLUTTER_VERSION` from
  `.github/workflows/deploy-play-store.yml` at the commit it builds, so
  F-Droid uses the same Flutter as the Play release (3.41.9 for 2.3.2).
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

A reviewer asked for fdroiddata's
[Flutter template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml),
so the recipe follows it:
- **F-Droid's own Flutter srclib**, `srclibs: flutter@stable`. `prebuild`
  checks it out at the `FLUTTER_VERSION` from the Play workflow, and the
  build runs it as `$$flutter$$/bin/flutter`. Auto-updates then pick up
  Flutter bumps by themselves. 260 fdroiddata recipes check out the srclib
  this way.
- **A pub cache inside the build tree**, removed by `scandelete`.
- **`flutter pub get --enforce-lockfile`**.
- **One APK per ABI** (armeabi-v7a, arm64-v8a, x86_64), each in its own
  build entry with `--split-per-abi --target-platform=…`, from
  `build/app/outputs/flutter-apk/`. Each is 16 to 20 MB; the universal APK
  was 55 MB. `--split-per-abi` matters. With `--target-platform` alone,
  Flutter keeps every ABI's plugin libraries (`libdartjni.so`,
  `libdatastore_shared_counter.so`) in each APK. The arm64 APK would then
  claim armeabi-v7a and x86_64 without the `libflutter.so` they need.
- **Flutter's own version codes per ABI**, as in
  [com.sunstep.travel.foss](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.sunstep.travel.foss.yml).
  The usual `%c * 10 + N` would need a versionCode override in
  `android/app/build.gradle.kts` and a new release.
- **The `UpdateCheckData` pattern for `pubspec.yaml`** that
  [Saber](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.adilhanney.saber.yml)
  uses: `pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+`.

The template's fixed `/upstream/path` build directory is left out, because
it only matters for reproducible builds. `fdroid lint` wants `Changelog` to
point at `/HEAD/` rather than `/main/`.

## Submitting

Submitted on 2026-10-19 as
[fdroiddata!53311](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/53311).
The recipe builds v2.3.2 (version codes 1015, 2015 and 4015). That is the
first tag whose release build is unsigned without `key.properties`, so it
needs no workarounds.

1. Create a GitLab account and fork
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata) (*Fork* at the top
   right). Forks of a public project are public.
2. In your fork, create a new branch, e.g. `simple-shot-timer`
   (*Code → Branches → New branch*, from `master`). Don't commit to
   `master`: it is protected, and the merge request needs an unprotected
   branch.
3. On that branch, add the file `metadata/cc.jami.simpleshottimer.yml`
   (*+ → New file*) with the contents of
   [cc.jami.simpleshottimer.yml](cc.jami.simpleshottimer.yml) (copy it from
   GitHub's *Raw* view). Commit message: `New app: Simple Shot Timer`.
   The file must use LF line endings and contain no comments: the pipeline's
   `fdroid rewritemeta` job fails on anything that isn't in F-Droid's exact
   format, and the build job's final check can't find `versionCode` behind a
   CRLF. In GitLab's Web IDE the line ending is shown (and switched) at the
   bottom right of the editor.
4. Open a merge request from that branch to `fdroid/fdroiddata:master`.
   Title: `New app: Simple Shot Timer`. Choose the *App inclusion* template
   and replace its text with
   [fdroid-merge-request.md](fdroid-merge-request.md) (Raw view again).
5. The merge request pipeline runs `fdroid lint` and a real build. If it
   fails or a reviewer asks for changes, update the file on the same branch;
   the merge request picks the change up.
6. Once merged, the app appears after F-Droid's next build and index cycle,
   usually within a few days.

Optional local check with fdroidserver on Linux, WSL or the
[fdroidserver Docker image](https://gitlab.com/fdroid/docker-executable-fdroidserver):
`fdroid readmeta`, `fdroid rewritemeta cc.jami.simpleshottimer`,
`fdroid lint cc.jami.simpleshottimer`,
`fdroid build -v -l cc.jami.simpleshottimer`.

**Signing.** F-Droid signs the app with its own key, so the F-Droid and the
Google Play versions can't update each other; switching means uninstalling
(and losing the history, which lives only on the phone). Reproducible builds
would let F-Droid ship your signature instead, but they need developer-signed
APKs to compare against, and once F-Droid has signed an app with its key it
can't switch later. Decided on 2026-10-21: F-Droid signs with its own key
for good. The project publishes no APKs, and Play users can't switch to
either build anyway, because Google holds the Play signing key.

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
- **Flutter version bumps** need nothing on the F-Droid side. Each build
  reads the version from the line `FLUTTER_VERSION: 'x.y.z'` in
  `deploy-play-store.yml` at its own commit. Keep that line in this exact
  form, single-quoted. Only if a Flutter bump needs a different NDK does
  the `ndk:` field (copied into each new entry) need a small fdroiddata
  merge request.
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
