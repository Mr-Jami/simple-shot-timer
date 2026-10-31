# Store listing graphics

Phone screenshots and the feature graphic for the Google Play listing, and the
iPhone screenshots for the App Store, in the listing's black / yellow halftone
style. One HTML page (`index.html`) holds all
of them; a browser screenshot of each section is the deliverable. The listing
text in every language is in [fastlane/metadata/](../../fastlane/metadata/README.md).

Current set: 2026-10-29, app 2.4 UI (five tabs with Video, the video editor).
App Store screenshots resized for the required 6.3" slot and header/search
artwork added 2026-10-31.

| Section id | Export | Shows |
|---|---|---|
| `#slide-1` … `#slide-5`, `#slide-9`, `#slide-7`, `#slide-8` | `out/01-ready.png` … `out/08-history.png`, 1080x1920 | Ready, running, finished, Review, Saved drills, Video editor, Test microphone, History |
| `#feature` | `out/feature-graphic.png`, 1024x500 | Feature graphic (listing header) |

On Google Play the video editor (`#slide-9`) takes slot 6, as `out/06-video.png`;
Settings (Par) (`#slide-6`) is left out there, since Play takes eight at most.

Google Play accepts 2–8 phone screenshots (PNG/JPEG, 9:16, 320–3840 px per side)
and one 1024x500 feature graphic without transparency. The exports meet both.

### App Store

The uploaded App Store set is committed in `app-store/screenshots/`: nine
screenshots at 1206x2622. App Store Connect requires at least one set for the
iPhone with Dynamic Island, medium display (6.1"/6.3": 1179x2556 or 1206x2622)
and rejects the 6.9" size there; the larger iPhones use these scaled up.

To remake them, `index.html?ios` renders the slides at 1320x2868. Export
`#slide-1` … `#slide-8` to `out/ios/01-ready.png` … `out/ios/08-history.png`
and `#slide-9` to `out/ios/09-video.png`: nine, all of them (the App Store takes
up to ten). There the video slide turns black, so the colours keep alternating
after the yellow History slide. Then scale them to the committed size (the
aspect ratios differ by 0.07%):

```sh
for f in out/ios/*.png; do
  ffmpeg -y -i "$f" -vf scale=1206:2622:flags=lanczos -pix_fmt rgb24 "app-store/screenshots/$(basename "$f")"
done
```

The App Store has no feature graphic (the app icon comes from the build), so
`#feature` is hidden in this mode. Its header and search result artwork
("Header und Suchergebnisse" in App Store Connect) is in `app-store/creative/`:
`universal-5244x2950.png`, Apple's 16:9 universal size for both placements, and
`header-3840x1646.png` (21:9) and `search-3840x2560.png` (3:2) cut from it. It
has no words, so one image serves every listing language; the mark, the time and
the shot timeline sit in the template's safe area (about 1402x962 at 1921,660),
the Ready and Review phones on the sides only show in wider crops. These images
are kept as they are; there is no source page for them.

The iOS variant keeps the captions and halftone and swaps the device: an iPhone
frame with Dynamic Island and home indicator, the iOS status bar, and the app laid
out at 393x852 pt inside the iPhone safe areas (59 pt top, 34 pt bottom). Flutter
draws the same Material widgets on iOS but with SF Pro text, a centred app bar
title and the iOS back chevron, so the variant does too. App Store Connect rejects
screenshots with an alpha channel; Chrome's exports are RGB.

App previews (videos) are optional and must be screen recordings of the app
itself, so the HTML launch video can't be used as one.

## How the screens are made

The phone screens are the app recreated in HTML at 390x845 dp and scaled 1.5x into
a phone frame, the same markup and CSS as `branding/launch-video`, so the listing
and the launch video stay in step. Nothing is a device screenshot; strings come
from `assets/i18n/en.json`, colours and spacing from `lib/theme/app_theme.dart` and
the screen widgets. Drill names, times and the 9:41 clock are made up.

Fonts load from Google Fonts at render time: Montserrat 800 italic for captions,
Roboto for the app UI. `assets/mark-white.png` and `assets/mark-black.png` are the
app icon (`assets/branding/icon.png`) and its colour-inverted copy. The listing
yellow is `#FEE036`.

### The video editor slide

`#slide-9` is not HTML: `assets/video-editor.jpg` and `assets/video-editor-ios.jpg`
are renders of the real editor (`VideoEditorScreen`, at 390x845 and 393x852 dp,
3x) from a widget test kept out of the repo, like the clip. It analyses one of
the developer's chest-mount range videos (no one's face in it), uses the app's
dark theme and fonts, and stands in a fake video platform whose picture is the
clip's frame at the playhead, so the editor draws its own overlay preview on
it. The iOS render uses Segoe UI for SF Pro, as Chrome does for the HTML
slides on Windows. Only chest-mount footage without faces goes into the
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
#   App Store: page.goto('http://127.0.0.1:8765/index.html?ios'), then
#   #slide-1 … #slide-9 to out/ios/
```

Check sizes with `ffprobe -show_entries stream=width,height out/*.png`.

## Updating after a UI change

Edit the matching `<section>` in `index.html`; each slide is one static screen state
with a comment naming it. Caption line breaks are explicit (`<br>`) so no line ends
in a single word. Keep every caption line under about 27 characters at 46 px.

## Captions

1. Press START and draw on the beep
2. Hears every shot. Splits update live
3. Instant breakdown: total, first shot and split
4. Shot-by-shot review with splits, fastest, slowest and your notes
5. Save your drills. Load any one with a tap
6. Standard, Par or Stage. Random start delay, par time and cycles (App Store only)
7. Dial in the mic with a live level meter
8. Every string saved. Browse, review, export CSV
9. Time a string from your video. Export it with your splits on it (Play: slot 6)

Feature graphic: "Simple Shot Timer — Saved drills, splits, history & more", with
the running, Ready and Saved drills screens and the line "Shooter ready?".
