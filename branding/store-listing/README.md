# Store listing graphics

Phone screenshots and the feature graphic for the Google Play listing, in the
listing's black / yellow halftone style. One HTML page (`index.html`) holds all
of them; a browser screenshot of each section is the deliverable.

Current set: 2026-10-01, app 2.0 UI (four-tab shell, saved drills).

| Section id | Export | Shows |
|---|---|---|
| `#slide-1` … `#slide-8` | `out/01-ready.png` … `out/08-history.png`, 1080x1920 | Ready, running, finished, Review, Saved drills, Settings (Par), Test microphone, History |
| `#feature` | `out/feature-graphic.png`, 1024x500 | Feature graphic (listing header) |

Google Play accepts 2–8 phone screenshots (PNG/JPEG, 9:16, 320–3840 px per side)
and one 1024x500 feature graphic without transparency. The exports meet both.

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

## Exporting

Serve the folder (the browser blocks `file:` URLs) and screenshot each section at
CSS scale 1:

```sh
cd branding/store-listing
python -m http.server 8765 --bind 127.0.0.1
# then, with Playwright (the MCP tool or a script):
#   page.goto('http://127.0.0.1:8765/index.html'); await fonts.ready
#   page.locator('#slide-1').screenshot({ path: 'out/01-ready.png', scale: 'css' })
#   ... #slide-8, #feature
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
6. Standard, Par or Stage. Random start delay, par time and cycles
7. Dial in the mic with a live level meter
8. Every string saved. Browse, review, export CSV

Feature graphic: "Simple Shot Timer — Saved drills, splits, history & more", with
the running, Ready and Saved drills screens and the line "Shooter ready?".
