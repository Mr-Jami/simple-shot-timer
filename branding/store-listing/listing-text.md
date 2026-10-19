# Store listing text

The text of the Google Play and App Store listings. The stores hold the live
copy; this file is where it is written and kept in sync with the app. Paste
from the code blocks (they keep the line breaks).

Last updated: 2026-10-19, app 2.3.0 (eight languages).

Both listings are English only. When a feature changes, update both
descriptions here, then in the consoles, together with the README features,
the website homepages and `website/public/llms.txt`.

| Field | Where | Limit |
|---|---|---|
| Google Play short and full description | Play Console → *Grow users → Store presence → Store listings* → default listing | 80 / 4000 characters |
| App Store description | App Store Connect → the app → the version being prepared → *Description*. It can only change with a new version. | 4000 characters |
| App Store What's New | Same page, *What's New in This Version* | 4000 characters |

The Play "What's new" text comes from the GitHub Release
(`.github/scripts/play_release_notes.py`); only the App Store needs it typed in.

## Google Play

### Short description

```text
Practical shot timer: par drills, splits, history & CSV. No ads, no tracking.
```

### Full description

```text
Simple Shot Timer is a clean, no-nonsense shot timer for dry-fire and live-fire practice. Made for practical shooters who want fast feedback, accurate splits and a full history of their drills, without ads, tracking or accounts.

DRILL MODES
• Standard: open string. Beep, shoot, tap STOP. Splits and total time on screen.
• Par: set a par time and the number of cycles. Each cycle has its own start and end beep, with an optional rest interval between cycles.
• Stage: a long single-window timer up to 200 seconds for stage walk-throughs and scenario practice.

START DELAY
Instant, fixed, or random within a min/max range.

SAVED DRILLS
Save the drills you run often (mode, start delay, par and stage timing) under a name, and load any one with a tap.

SHOT DETECTION
• Listens through your phone's microphone and picks out each shot as it happens.
• The start and par beeps never count as a shot, a shot fired during the beep still does, and an echo filter keeps one shot from counting twice.
• The clock starts when the mic hears the beep, so speaker lag never ends up in your times.
• Auto-configure: fire a few shots and the app suggests a sensitivity and frequency band for that gun and range.
• A mic test screen with a live level meter lets you dial in sensitivity before going hot.
• Add shots by hand at any time, after the string or in review.

HISTORY & REVIEW
• Every string is saved automatically (rolling cap from 50 to 5000, default 500).
• Review each string with split times, first shot, fastest, slowest and average.
• Editable label, notes and penalty per string.

CSV EXPORT
Export a single string or your whole history as CSV through the share sheet: email it to yourself, save it to cloud storage or open it in a spreadsheet.

KEEPS RUNNING
Lock the screen or switch apps mid-string: the timer keeps detecting shots and playing par beeps.

PRIVACY FIRST
• 100% on-device. No accounts, no cloud, no analytics, no ads, no tracking.
• The microphone is used live, in memory, only while the app is listening (a string, the mic test or auto-configure). No audio is recorded or sent anywhere.
• Delete all your data and settings from Settings at any time.
• Open source (GPL-3.0): the full code is on GitHub at github.com/Mr-Jami/simple-shot-timer, so you can check every claim above.

QUALITY OF LIFE
• Screen flash on the beep for loud ranges and heavy ear protection, plus optional haptics.
• A notice warns you if the media volume is muted while a string runs.
• Keeps the screen awake during a string.
• Monochrome Material 3 theme with System, Light, Dark and High-contrast options.

LANGUAGES
English, Finnish, French, German, Polish, Portuguese, Russian and Spanish.

PERMISSIONS
• Microphone: required for shot detection. Requested the first time the mic is needed.
• Notifications: on Android 13 and later, needed for the notification that keeps the timer running in the background.
• Vibration: optional haptic on the beep.
• Wake lock: keeps the screen on during a string.

Built for the range, the dojo and the basement dry-fire setup. Free, lean, no upsells.
```

## App Store

### Description

```text
Simple Shot Timer is a clean, no-nonsense shot timer for dry-fire and live-fire practice. Made for practical shooters who want fast feedback, accurate splits and a full history of their drills, without ads, tracking or accounts.

DRILL MODES
• Standard: open string. Beep, shoot, tap STOP. Splits and total time on screen.
• Par: set a par time and the number of cycles. Each cycle has its own start and end beep, with an optional rest interval between cycles.
• Stage: a long single-window timer up to 200 seconds for stage walk-throughs and scenario practice.

START DELAY
Instant, fixed, or random within a min/max range.

SAVED DRILLS
Save the drills you run often (mode, start delay, par and stage timing) under a name, and load any one with a tap.

SHOT DETECTION
• Listens through your iPhone's microphone and picks out each shot as it happens.
• The start and par beeps never count as a shot, a shot fired during the beep still does, and an echo filter keeps one shot from counting twice.
• The clock starts when the mic hears the beep, so speaker lag never ends up in your times.
• Auto-configure: fire a few shots and the app suggests a sensitivity and frequency band for that gun and range.
• A mic test screen with a live level meter lets you dial in sensitivity before going hot.
• Add shots by hand at any time, after the string or in review.

HISTORY & REVIEW
• Every string is saved automatically (rolling cap from 50 to 5000, default 500).
• Review each string with split times, first shot, fastest, slowest and average.
• Editable label, notes and penalty per string.

CSV EXPORT
Export a single string or your whole history as CSV through the share sheet: mail it to yourself, save it to Files or open it in a spreadsheet.

KEEPS RUNNING
Lock the screen or switch apps mid-string: the timer keeps detecting shots and playing par beeps.

PRIVACY FIRST
• 100% on-device. No accounts, no cloud, no analytics, no ads, no tracking.
• The microphone is used live, in memory, only while the app is listening (a string, the mic test or auto-configure). No audio is recorded or sent anywhere.
• Delete all your data and settings from Settings at any time.
• Open source (GPL-3.0): the full code is on GitHub at github.com/Mr-Jami/simple-shot-timer, so you can check every claim above.

QUALITY OF LIFE
• Screen flash on the beep for loud ranges and heavy ear protection, plus optional haptics.
• A notice warns you if the volume is muted while a string runs.
• Keeps the screen awake during a string.
• Monochrome theme with System, Light, Dark and High-contrast options.

LANGUAGES
English, Finnish, French, German, Polish, Portuguese, Russian and Spanish.

Built for the range, the dojo and the basement dry-fire setup. Free, lean, no upsells.
```

### What's New (2.3.0)

The App Store is on 2.1.0, so this covers 2.2.0 and 2.3.0.

```text
• Use the app in Polish, Portuguese and Finnish.
• Open the privacy policy and delete all your data and settings from Settings.
```
