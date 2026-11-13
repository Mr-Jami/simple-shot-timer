# Store listing graphics

Phone screenshots for the Google Play and App Store listings in every app
language, and the Play feature graphic, in the listing's
black / yellow halftone style. One HTML page (`index.html`) holds all
of them; a browser screenshot of each section is the deliverable. The listing
text in every language is in [fastlane/metadata/](../../fastlane/metadata/README.md).

Current sets: Google Play 2026-11-13 and App Store 2026-11-12, both app 2.5
in eight languages. Feature graphic 2026-10-29 (app 2.4 UI).

In both sets each phone screen is a render of the app itself in that
language; [App Store](#app-store) has the rules they follow and how the
renders are made. The sets differ in the frame, the size and two screens.

### Google Play

The uploaded Play set is committed in
`fastlane/metadata/android/<language>/images/phoneScreenshots/` (fastlane's
layout, which F-Droid reads too): eight screenshots per language,
`01-running.png` to `08-ready.png`, at 1080x1920. Play takes eight at most,
so the mic test of the App Store set is left out. The *Update store
listings* workflow uploads them when its **Play screenshots** box is ticked
(see the main README).

The video slide is the other difference: Play's shows a moment in the middle
of the string, with the shooter's arm and pistol in the frame and the splits
on the picture. The App Store's shows the moment after the beep instead,
because Apple wants store pictures fit for all ages.

To remake them:

1. Render the app: `PLATFORM=android AT_MS=15060 ZOOM=1
   branding/store-listing/render/render_all.sh <clip.mp4>` writes
   `renders/android/<lang>/` (not committed), nine PNGs per language at
   1170x2535, in Roboto.
2. `index.html?play&lang=<lang>` puts each render in the Android frame with
   the caption and the halftone, at 1080x1920. Export every slide that has a
   `data-shot` to `out/play/<language folder>/<data-shot>.png` (call
   `fitCaptions()` first, as for the App Store).
3. Copy each folder's files to
   `fastlane/metadata/android/<language folder>/images/phoneScreenshots/`.

Google Play accepts 2–8 phone screenshots (PNG/JPEG, 9:16, 320–3840 px per side)
and one 1024x500 feature graphic without transparency. The exports meet both.

The feature graphic is `#feature` on the page without a query, exported to
`out/feature-graphic.png` and uploaded by hand. It is made of HTML phone
screens: see [How the screens are made](#how-the-screens-are-made).

### App Store

The uploaded App Store set is committed in `app-store/screenshots/<language>/`
(the folder names of `fastlane/metadata/ios`): nine screenshots per language,
`01-running.jpg` to `09-ready.jpg`, at 1206x2622. App Store Connect requires
at least one set for the iPhone with Dynamic Island, medium display
(6.1"/6.3": 1179x2556 or 1206x2622); the larger iPhones use these scaled up.
The *Update store listings* workflow uploads them when its **Screenshots**
box is ticked (see the main README).

They follow Apple's "App Store asset best practices" (read 2026-11-12):

- **The real app, in every language.** Each phone screen is a render of the
  app itself in that language, not an HTML recreation, so
  the words, dates and plurals are the app's own and the UI is the current one.
- **Best features first.** Running timer, video, Review, then total, saved
  drills, modes, History, the mic test and the Ready screen. The first three
  are what a product page shows without scrolling.
- **Short captions** that add to the picture: two lines each, in
  `captions.js`, translated with the app's own words for strings, drills and
  the beep. They have not been checked by native speakers.
- **Fit for all ages.** No weapon in any picture: the video slide uses a
  moment just after the beep, with the targets in view and the pistol still
  holstered. No prices, URLs or other platforms either.

To remake them:

1. Render the app (needs a range clip that starts from the holster; it stays
   out of the repo): `branding/store-listing/render/render_all.sh <clip.mp4>`
   writes `renders/ios/<lang>/` (not committed), nine PNGs per language at
   1179x2556. `store_shots_test.dart` starts the whole app with fakes behind
   its ports (microphone, beep, database) and drives it through one string,
   then the other screens; `editor_shot_test.dart` renders the video editor
   on the clip. `render_font.py` names a font, for the render only, where the
   app's text names none (the overlay and the chip labels would draw as boxes
   in a test). The iOS text is Segoe UI, as Chrome draws `-apple-system` on
   Windows.
2. `index.html?ios&lang=<lang>` puts each render in the iPhone frame with the
   iOS status bar, the caption and the halftone, at 1320x2868. Every slide
   carries its file name in `data-shot`. Export each one to
   `out/ios/<language folder>/<data-shot>.png` (call `fitCaptions()` once the
   fonts have loaded: it sizes the captions of a language to its longest line).
3. Scale them to the committed size (the aspect ratios differ by 0.07%):

```sh
for f in out/ios/*/*.png; do
  d=app-store/screenshots/$(basename "$(dirname "$f")")
  ffmpeg -y -i "$f" -vf scale=1206:2622:flags=lanczos -q:v 6 -pix_fmt yuvj444p "$d/$(basename "${f%.png}").jpg"
done
```

App Store Connect rejects screenshots with an alpha channel; JPEG has none.

The App Store has no feature graphic (the app icon comes from the build), so
`#feature` is hidden in this mode. Its header and search result artwork
("Header und Suchergebnisse" in App Store Connect) is in `app-store/creative/`:
`universal-5244x2950.png`, Apple's 16:9 universal size for both placements, and
`header-3840x1646.png` (21:9) and `search-3840x2560.png` (3:2) cut from it. It
has no words, so one image serves every listing language; the mark, the time and
the shot timeline sit in the template's safe area, the Ready and Review phones
on the sides only show in wider crops. These images are kept as they are; there
is no source page for them. The *Update store listings* workflow puts the
header and the search image on the version when its **Creative assets** box is
ticked (see the main README); the universal image is not uploaded.

Apple's art safe areas (creative assets specifications, read 2026-11-12), as
x, y, width, height from the top left: header 1097, 493, 1646 x 661; search
836, 765, 2168 x 1030 (at 3840x2560); universal 1921, 660, 1402 x 962. The
mark, the time and the timeline are inside all three. Check any new version
against them: the first search image had the mark 87 px above its safe area.

App previews (videos) are optional and must be screen recordings of the app
itself, so the HTML launch video can't be used as one.

**iPhone Duo.** Apple takes screenshots for the folding iPhone (1398x2034 for
the outer display, 2007x2853 for the inner one) and shows a "made for iPhone
Duo" badge on the product page once they are there; from April 2027 they are
required for apps built with the iOS 27.1 SDK. None are uploaded yet, on
purpose: only a build made with the iOS 27.1 SDK fills those displays (an
older build sits in the middle of the inner one), so the badge would promise
more than the app does. The layout itself is ready: `store_shots_test.dart`
with `SIZE=669x951`, `466x678` and `951x669` renders every screen without an
overflow (checked 2026-11-12, English and Russian). When the deploy moves to
Xcode 27.1, render at those sizes, add slides for them and upload.

## How the screens are made

The phone screens of the feature graphic, and the slides of the page without
a query (`#slide-1` … `#slide-9`, the Play set until app 2.5), are not
renders. They are the app recreated in HTML at 390x845 dp and scaled 1.5x into
a phone frame, the same markup and CSS as `branding/launch-video`, so the listing
and the launch video stay in step. Nothing is a device screenshot; strings come
from `assets/i18n/en.json`, colours and spacing from `lib/theme/app_theme.dart` and
the screen widgets. Drill names, times and the 9:41 clock are made up.

Fonts load from Google Fonts at render time: Montserrat 800 italic for captions,
Roboto for the app UI. `assets/mark-white.png` and `assets/mark-black.png` are the
app icon (`assets/branding/icon.png`) and its colour-inverted copy. The listing
yellow is `#FEE036`.

### The video editor slide

`#slide-9` is not HTML: `assets/video-editor.jpg` is a render of the real
editor (`VideoEditorScreen`, at 390x845 dp, 3x) from
`render/editor_shot_test.dart` with `PLATFORM=android`; the clip stays out of
the repo. It analyses one of
the developer's chest-mount range videos (no one's face in it), uses the app's
dark theme and fonts, and stands in a fake video platform whose picture is the
clip's frame at the playhead, so the editor draws its own overlay preview on
it. The overlay's text names no font and draws as boxes in a test, so
`render/render_font.py` names one for the render only (Roboto for Android),
and the details list is scrolled by 186 so the stats show. Only chest-mount footage without faces goes into the
listing, never videos of other shooters.

## Exporting

Serve the folder (the browser blocks `file:` URLs) and screenshot each section at
CSS scale 1:

```sh
cd branding/store-listing
python -m http.server 8765 --bind 127.0.0.1
# then, with Playwright (the MCP tool or a script):
#   page.goto('http://127.0.0.1:8765/index.html'); await fonts.ready
#   page.locator('#slide-1').screenshot({ path: 'out/01-ready.png', scale: 'css' })
#   ... #slide-8, #slide-9, #feature
#   The Google Play and App Store sets: see above
```

Check sizes with `ffprobe -show_entries stream=width,height out/*.png`.

## Updating after a UI change

The two listing sets are rendered from the app again (see above). For the
HTML screens, edit the matching `<section>` in `index.html`; each slide is one static screen state
with a comment naming it. Caption line breaks are explicit (`<br>`) so no line ends
in a single word. Keep every caption line under about 27 characters at 46 px.

## Captions

Both sets take their captions from `captions.js`: two short lines per screen
and app language, sized by `fitCaptions()` to the longest line of the set.
The captions written into the HTML slides are the Play set's until app 2.5.

Feature graphic: "Simple Shot Timer — Saved drills, splits, history & more", with
the running, Ready and Saved drills screens and the line "Shooter ready?".
