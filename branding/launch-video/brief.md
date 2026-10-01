# Composition brief: Simple Shot Timer launch video (2.0 UI, revision 3)

## Objective
Recreate the 2026-09-24 brag video (first cut, kept locally) scene for scene on the app's
2.0 UI and add one scene for the saved-drills feature. Same hook, same audio, same outro.

## Output
- Composition directory: `branding/launch-video/composition/`
- Rendered video: `branding/launch-video/brag.mp4`
- Format: vertical, 1080x1920, 30 fps
- Duration: 29.9 s (25 s ceiling knowingly exceeded; see storyboard.md)

## Source Material
- Project root: `simple-shot-timer/` (Flutter)
- Primary files read: `lib/screens/main_shell.dart`, `home_screen.dart`, `review_screen.dart`,
  `settings_screen.dart`, `detection_settings_screen.dart`, `mic_test_screen.dart`,
  `custom_drills_screen.dart`, `lib/widgets/{tab_header,drill_tile,big_time_display,
  mic_level_meter,settings_widgets,settings_slider}.dart`, `lib/theme/app_theme.dart`,
  `lib/models/{app_settings,drill_config}.dart`, `assets/i18n/en.json`,
  the 2026-09-24 build (local only), reused as the base
- Product name: Simple Shot Timer
- Strongest claim: it hears every shot, saves every split, remembers your drills, free
- Key UI to recreate: Timer tab (countdown → running → finished → idle) inside the
  four-tab shell; Review page; Settings tab (3 drill-mode states + the state after a drill
  is applied); Drills tab (list + apply + snackbar); Shot detection page; Test microphone page
- Copy that must appear verbatim (from en.json): `STAND BY`, `TIME`, `LAST`, `TOTAL`,
  `SHOTS`, `FIRST`, `SPLIT`, `START`, `STOP`, `Review`, `Add shot`, `Saved 9:41 AM`,
  `Ready`, `Press START to begin`, `Last 2.37s · 5 shots`, `FASTEST`, `SLOWEST`,
  `AVERAGE`, `Shots (5)`, `Label`, `Notes`, `Penalty: 0.00s`, `Settings`, `Drill mode`,
  `Start delay`, `Par time`, `Stage time`, `Beep`, `Visual flash on beep`,
  `Haptic on beep`, `Shot detection`, `15% sensitivity · 300–6000 Hz`, `Saved drills`,
  `Applied “Bill Drill”`, `Test microphone`, `Live level meter to dial in sensitivity`,
  `Auto-configure`, `Peak hold`, `Threshold`, `Dominant: — Hz`, `Play test beep`,
  `Sensitivity`, tab labels `Timer` `Drills` `History` `Settings`

## Creative Direction
- Tone preset: cinematic; direction: range-day cold open, serious, no firearm jokes
- Angle / hook / outro: see `storyboard.md`
- Avoid: generic SaaS language, abstract filler, gunshot audio, beep flashes, any colour
  beyond the app's monochrome + STOP red + threshold red

## Visual Identity
- Background #000000; surfaces #0A0A0A / #111111 / #161616 / #1C1C1C; outline #333333;
  outline variant #222222
- Text #FFFFFF / #AAAAAA; primary = white, onPrimary = black
- STOP red #F44336; threshold / error red #FF5252
- Inverted pills (white with black content): selected tab icon, selected choice chip,
  START button, snackbar
- Font: Roboto (shipped locally, `assets/fonts/Roboto.ttf`), tabular numerals
- App UI recreated at 390 dp logical width inside a phone frame scaled 1.641x;
  bottom tab bar 72 dp + 20 dp system inset on #111111

## Storyboard
Use the storyboard in `storyboard.md` as the creative contract.

1. Cold open — 0.00–4.60 — ARE YOU READY? on black → Timer tab STAND BY (greyed tab bar) → beep
2. Hears every shot — 4.60–10.00 — running timer, 5 shots, mic line spikes, STOP, TOTAL 2.37, button morph
3. Every split. Saved. — 10.00–13.34 — Review page push, rows cascade + scroll, back pop to idle Timer tab
4. Pick your drill — 13.34–16.62 — Settings tab, Standard → Par → Stage
5. Save your drills — 16.62–20.44 — Drills tab, apply Bill Drill, snackbar, Settings shows Fixed delay
6. Dial in the mic — 20.44–25.95 — Shot detection page → Test microphone, 2 peaks, slider drag
7. Outro — 26.97–29.90 — icon + SIMPLE SHOT TIMER, "Free on Google Play", par beep 29.10

## Audio
- Role: cinematic support; silent voice-only cold open, then a steady bed
- Custom clips: `sfx/ro-are-you-ready.wav` @0.30, `sfx/ro-standby.wav` @2.03,
  `sfx/start-beep.wav` @4.60, `sfx/par-beep.wav` @29.10
- Music: `music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` from 4.60, 25.3 s,
  volume lane 0.35, fade out track 23.9 → 25.3
- Music cue guidance: bundled vol-12 preset. Comp time = track + 4.60. Beat-locked strong
  cues: 13.34, 15.53, 17.71, 20.44, 22.07, 23.16, 24.26, 26.97. Beat-grid: 14.43, 16.62, 20.98
- Audio-reactive: subtle; the radial glow behind the phone follows music RMS
  (`assets/music-rms.js`, 30 fps, starting at 4.60, 759 frames)
- SFX: steel pings (`shot-1..5.wav`) on the 5 shots and the 2 mic peaks; `click_001` on
  STOP / Review / back / chips / drill row; `select_008` on tab taps; `drop_001` /
  `drop_002` on page pushes; `impactGlass_light_001` with the snackbar; `click2` on the
  slider; `impactBell_heavy_000` on the logo slam

## Hyperframes Instructions
Same contract as the previous build: standalone root `data-composition-id="main"`, one
paused GSAP timeline registered at `window.__timelines["main"]`, per-frame `tl.call` for
the timer / meters / glow, every `<audio>` with `data-start` / `data-duration` /
`data-track-index` / `data-volume`, music volume via `data-automation`. Run
`npx hyperframes check` before render.
