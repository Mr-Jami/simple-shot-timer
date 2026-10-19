## Abstract

### Please introduce the functions and usage of your app in summary, and also attach some screenshots.

Simple Shot Timer is a shot timer for dry-fire and live-fire practice in practical shooting (IPSC, USPSA and similar disciplines). It gives a start beep after an instant, fixed or random delay, hears every shot through the microphone and shows the time of each shot and the splits between them.

- Drill modes: Standard (open string), Par (par time with repeats and a rest between them) and Stage (up to 200 seconds).
- Auto-configure suggests a sensitivity and frequency band from a few test shots; a mic test with a live level meter helps to fine-tune it.
- The clock starts when the microphone hears the start beep, so speaker latency doesn't end up in the times; the beep is filtered out, so a shot during the beep still counts.
- Saved drills, a history of every string with review (splits, first shot, fastest, slowest, average), notes and penalties, and CSV export through the share sheet.
- Keeps detecting while the screen is locked (foreground service with a notification).
- English, German, Spanish, Finnish, French, Polish, Portuguese (Brazil) and Russian.

Everything stays on the device. The app has no `INTERNET` permission, no account, no ads and no analytics. It asks for `RECORD_AUDIO`, `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE`, `POST_NOTIFICATIONS`, `WAKE_LOCK` and `VIBRATE`.

<img src="https://raw.githubusercontent.com/Mr-Jami/simple-shot-timer/main/fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" width="180" alt="Ready screen">
<img src="https://raw.githubusercontent.com/Mr-Jami/simple-shot-timer/main/fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" width="180" alt="Finished string with splits">
<img src="https://raw.githubusercontent.com/Mr-Jami/simple-shot-timer/main/fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" width="180" alt="Shot-by-shot review">
<img src="https://raw.githubusercontent.com/Mr-Jami/simple-shot-timer/main/fastlane/metadata/android/en-US/images/phoneScreenshots/6.png" width="180" alt="Par drill settings">

Website: https://simpleshottimer.com/ · Source: https://github.com/Mr-Jami/simple-shot-timer

### Please elaborate why you wrote this app. Please highlight the unique functions it provides over other similar apps in F-Droid.

I wanted a modern app with everything a simple club timer (such as a PACT Club Timer III) does, that is free and open source, works offline and keeps the data on the phone. A dedicated shot timer costs $100 or more; this is an alternative for when you don't want to buy one or left yours at home.

What sets it apart from a basic timer app: it measures the start beep through the microphone instead of trusting the playback call, notch-filters the beep tone so a shot fired during the beep still counts, auto-configures detection for the gun and range, and has par drills with repeats and rest intervals for dry fire. I'm the developer and maintain it; it's released under GPL-3.0-only.

## Checklist

### Policy

* [x] The app complies with the [inclusion criteria](https://f-droid.org/docs/Inclusion_Policy).
* [x] The original app author has been notified (and does not oppose the inclusion). If you are not the author, please paste the link of the reply from the author.
  - I am the author.
* [x] The upstream app source code repo contains the app metadata in a [Fastlane](https://gitlab.com/snippets/1895688) or [Triple-T](https://gitlab.com/snippets/1901490) folder structure. The summary and description must be included and images, icon, and changelog should also be provided for better user experience. The `en-US` locale must be included.
  - `fastlane/metadata/android/` with en-US plus de-DE, es-ES, fi-FI, fr-FR, pl-PL, pt-BR and ru-RU; icon, feature graphic, 8 screenshots and changelogs in en-US.

### Docs

* [x] Please read [the guide](https://gitlab.com/fdroid/fdroiddata/-/blob/master/CONTRIBUTING.md) first if this is your first contribution.
* [x] Please make sure your metadata follows the best practice in [our templates](https://gitlab.com/fdroid/fdroiddata/tree/master/templates).
* [x] Please read the [Build Metadata Reference](https://f-droid.org/docs/Build_Metadata_Reference/) and make sure your metadata is valid.
* [x] Please read the [Quick Start Guide](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/).

### Merge Request Setup

* [x] The title of this merge request should follow "New app: app name" format.
* [x] Please make sure your fdroiddata fork is public and your branch is not protected. See <https://docs.gitlab.com/user/project/repository/branches/protected/>.
* [x] Please read [our Git guide](https://gitlab.com/fdroid/wiki/-/wikis/Tips-for-fdroiddata-contributors/Git-Usage) if you don't know how to rebase your branch. Don't rebase your branch if there is no conflict.
* [x] All related [fdroiddata](https://gitlab.com/fdroid/fdroiddata/issues) and [RFP issues](https://gitlab.com/fdroid/rfp/issues) have been referenced in this merge request
  - There are none.
* [x] Please only submit one app in one MR.

### Metadata

* [x] Metadata must be put in `metadata/<applicationId>.yml`.
* [x] Metadata must be a valid YAML file.
* [x] Metadata must use LF as line ending.
* [x] Don't add summary/description/changelog/images or anything that should be provided in upstream repo. Please check the Changes tab to make sure there is no other unrelated files added in the MR.
* [x] Releases are tagged and auto update is enabled unless there is a special reason.
  - Tags `vX.Y.Z` by release-please; `UpdateCheckMode: Tags` reads the version and the `+N` version code from `pubspec.yaml`.
* [x] There is an issue tracker and contact info of the author so that we can report bugs and contact the author.
* [x] An AuthorName must be added. It doesn't need to be the real name.
* [x] External repos are added as git submodules instead of srclibs. You can update git submodules without opening an MR in this repo and the submodule is covered by our scanner.
  - The only external dependency is the Flutter SDK, added as the `flutter` srclib like in other Flutter recipes.
* [ ] Enable [Reproducible Builds](https://f-droid.org/docs/Reproducible_Builds). We'll use your signature for improved security/reliability, also allowing users to switch between different channels. Do note that if you don't enable reproducible build then the apk will be signed with our key so you can't enable it later. If you can't enable this, please add the reasons here.
  - Not for now: the project publishes no developer-signed APKs to compare against (Google Play gets an AAB signed through Play App Signing). Please sign with the F-Droid key.
* [ ] Setup abi split if the APK is large and the splitted ones can be much smaller.
  - It's one universal APK for now. If you prefer per-ABI builds to cut the download size, I'm happy to change the recipe.
* [x] Only the latest versions should be kept in the metadata before it's merged. If you update the metadata, please replace the old versions with the new ones.
* [x] Don't add any disabled versions in the metadata.
* [x] The `commit` field should be the full hash. Please don't use tag or branch in commit.

### Pipeline

* [ ] All pipelines should pass.
* [ ] All warnings and errors in the Reports tab should be fixed or explained.
* [x] F-Droid CI runners are under GitLab's FOSS program, so there's no need for you to pay for any CI time. If Gitlab starts asking for phone numbers or credit cards don't submit anything, just leave a note in the MR so we know we need to trigger the CI.

## Notes for reviewers

- I am the developer and the holder of the name "Simple Shot Timer" and its icon. The NOTICE file reserves trademark rights for modified versions (GPLv3 section 7(e)); I allow F-Droid to build and distribute the unmodified app under its name and icon.
- The release build is unsigned when `android/key.properties` is absent (CI writes that file for Google Play), so `output:` points at `app-release-unsigned.apk`.
- The Flutter srclib matches the version CI builds with (3.41.9). When CI moves to a newer Flutter, I'll send a merge request to bump it.
