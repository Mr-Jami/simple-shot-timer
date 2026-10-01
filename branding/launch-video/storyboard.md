# Storyboard: Simple Shot Timer launch video (revision 3, 2026-10-01)

Source plan: the maintainer's local brag-video-plan.md and the 2026-09-24 render (both kept outside git).
This revision recreates that video on the 2.0 UI (four-tab shell, single morphing
START/STOP button, compact mic line, two-level Settings, monochrome theme) and adds one
scene for the new **saved drills** feature. Everything else, including the audio, stays.

## What is this app?
A free, offline shot timer for Android. It gives a real start beep, hears every shot
through the phone mic, saves every split for review, and now remembers named drills.

## The angle
"The range, in your pocket." Open the way every IPSC stage starts: a Range Officer's
voice, silence, then the beep. The app's own 2325 Hz start beep starts the video.
After that, show what happens next: shots detected, splits saved, drills picked and
saved, the mic dialled in.

## Hook (first 2-3 seconds)
Black screen, no music. Real RO recording: "Are you ready?", with ARE YOU READY?
appearing as it is spoken. Then "Standby" and the phone cuts in on STAND BY.

## Key moments (the middle)
- STAND BY on the Timer tab, 1.6 s of silence, then the beep. Music starts on the beep.
- Running view: time counts up, 5 shots register with steel pings, SHOTS / FIRST / SPLIT
  update live, the compact mic line spikes past the red threshold on each shot, STOP,
  then TOTAL 2.37 and the button morphs to a white START.
- Review page: FIRST / FASTEST / SLOWEST / AVERAGE grid, the shot list cascades in.
- Settings tab: Standard → Par → Stage chips, the section below changes each time.
- **Drills tab (new):** four saved drills, the active one checked; tap "Bill Drill" and the
  check moves, the snackbar says Applied "Bill Drill", and Settings now shows that drill.
- Shot detection → Test microphone: two shot peaks cross the red line, sensitivity 15 → 25 %.

## Outro / punchline
SIMPLE SHOT TIMER slams in on a strong beat → "Free on Google Play". The last sound is
the app's 700 ms par beep ("time's up").

## User flow worth showing
START → STAND BY → beep → shots detected live → STOP → TOTAL → Review → back →
Settings tab → Drills tab (apply a saved drill) → Settings tab → Shot detection →
Test microphone. Every transition is the app's real one: pushed pages slide, tabs cut.

## Tone
- Preset: cinematic
- Creative direction: range-day cold open; serious, no jokes about firearms
- Interpretation: silence and big type for the open, then clean app-store style feature
  scenes. Large ALL-CAPS captions, held long enough to read, dramatic but restrained.

## Format: vertical — 1080x1920
## Duration: 29.9 s

The brag ceiling is 25 s. The 2026-09-24 cut was already 25.0 s; the user asked for the
same video plus the drills feature, so the new scene (3.8 s) and two real navigation
steps (Settings revisit, Shot detection page, 1.6 s) push it to 29.9 s. Nothing else grew.

## Visual identity (from lib/theme/app_theme.dart, 2.0)
- Background: #000000; surfaces #0A0A0A / #111111 / #161616 / #1C1C1C; outline #333333,
  outline variant #222222
- Text: #FFFFFF primary, #AAAAAA secondary (onSurfaceVariant)
- Accent: none (true monochrome). Only colour: STOP red #F44336 (Colors.red) and the
  error red #FF5252 used for the mic threshold line
- Inverted pills: selected tab icon, selected choice chip, START button and snackbar are
  white with black content
- Display font: Roboto, heavy weight, letter-spaced caps
- Body font: Roboto; numbers use tabular figures
- Strongest visual element: the huge centred time readout with the letter-spaced
  `SHOTS  FIRST  SPLIT` stat row, and the single full-width 96 dp button
- Logo: assets/branding/icon.png (outro only; the Timer tab has no app bar now)

## Share copy (draft)
Are you ready? … Standby. … *beep*. Simple Shot Timer hears every shot, saves every
split, and remembers your drills. Free on Google Play.

## Audio direction
- Role: cinematic support. Silent cold open with voice only, then a steady music bed
- Music: happy-beats-business-moves-vol-12 (110 BPM, steady, clean), unchanged
- Music treatment: starts at 4.60 s exactly on the start beep (track offset 0), volume
  0.35, holds to track 23.9 s, fades out to 25.3 s (composition 28.5 → 29.9) under the par beep
- Music cue guidance: preset `assets/music/cues/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`.
  Composition time = track time + 4.60. Beat = 0.5455 s. Strong cues used (composition):
  13.34 (Settings tab), 15.53 (Stage chip), 17.71 (apply drill), 20.44 (Settings tab
  again), 22.07 (Test microphone push), 23.16 / 24.26 (mic shots), 26.97 (logo slam).
  Beat-grid taps: 14.43 Par, 16.62 Drills tab, 20.98 Shot detection.
- Audio-reactive treatment: subtle; the soft radial glow behind the phone breathes with
  music RMS (re-extracted for the 25.3 s bed). No waveform visuals.
- SFX posture: sparse, motion-matched. Clicks on chip / row / button taps, a selection
  tick on tab taps, soft drops on page pushes, a light glass tick on the snackbar, bell on
  the logo
- Custom clips (user-supplied, unchanged): RO "Are you ready?" at 0.30, RO "Standby" at
  2.03, start beep at 4.60, par beep at 29.10
- Restraint rule: no music or SFX under the RO voice. No gunshot sounds. No beep flashes
  (removed in revision 2). Shot pings sit at realistic split times, not on the grid.

## Storyboard

### Scene 1 — Cold open — 0.00–4.60 s (4.6 s)
Black. 0.38 s: ARE YOU READY? lands word by word with the voice. At 2.05 s, cut to the
phone on the Timer tab in countdown: no app bar, chips `El Presidente` (bookmark, the
active saved drill) · `Standard mode` · `Random delay`, hourglass, `STAND BY`, red STOP
button, bottom tab bar (Timer · Drills · History · Settings) greyed to 38 % because a
string is in progress. Slow push-in during the silence. Beep at 4.60, small punch, no flash.
Sequential/interaction: words appear with the voice
Audio: silence and tension, then the release; music starts on the beep
Transition mood: hard → Scene 2

### Scene 2 — It hears every shot — 4.60–10.00 s (5.4 s)
Running view: `TIME` counts up from the beep; shots at beep + 1.42 / 1.68 / 1.91 / 2.15 /
2.37 (composition 6.02 / 6.28 / 6.51 / 6.75 / 6.97). Each shot: label → `LAST`, SHOTS up,
FIRST 1.42, SPLIT 0.26 / 0.23 / 0.24 / 0.22, number pulse, the 3 dp mic line under the
stats spikes to 98 % past the red threshold mark and decays. STOP tap at 7.60; at 7.70
the finished view: `TOTAL 2.37`, stats, `Review` / `Add shot`, `Saved 9:41 AM`; the button
morphs red STOP → white START; the tab bar comes back to full opacity.
Caption 7.90–9.85: HEARS EVERY SHOT. / Through the phone microphone.
Interaction: 5 shots, STOP tap, Review tap at 9.90
Audio: steel ping per shot, click on STOP and Review
Transition mood: Review page slides in → Scene 3

### Scene 3 — Every split. Saved. — 10.00–13.34 s (3.3 s)
Review page (app bar with back arrow, `Review`, share icon): `Sep 24, 2026 9:41 AM`,
`Standard · Random (1.58s delay)`, grid TOTAL 2.37s · FIRST 1.42s · FASTEST 0.22s ·
SLOWEST 0.26s · AVERAGE 0.24s · SHOTS 5, `Label` field "El Presidente dry run", `Notes`,
`Penalty: 0.00s`, divider, `Shots (5)` + Add, five rows cascading in (0.09 s stagger), then
a short scroll so all five rows show. Share icon ring 12.2–12.9.
Caption 10.10–13.10: EVERY SPLIT. SAVED.
Back tap 12.90, page slides out revealing the idle Timer tab (`Ready`, chips, `Last 2.37s · 5 shots`).
Audio: soft drop on the push, click on back
Transition mood: tab cut (beat-locked 13.34) → Scene 4

### Scene 4 — Pick your drill — 13.34–16.62 s (3.3 s)
Settings tab (large `Settings` title, no app bar, tab bar with Settings selected):
DRILL MODE chips Standard · Par · Stage, START DELAY chips, Random min / max sliders,
BEEP section, `Shot detection` row with `15% sensitivity · 300–6000 Hz`. Par tap at
14.43 adds PAR TIME (Duration 2.0s, Repeat count 5 beeps, Interval 5.0s); Stage tap at
15.53 (strong) swaps it for STAGE TIME (Duration 60s). Selected chip is the inverted pill.
Caption 13.44–16.45: PICK YOUR DRILL. / Standard · Par · Stage
Audio: click per chip tap, selection tick on the tab tap
Transition mood: tab cut → Scene 5

### Scene 5 — Save your drills (new) — 16.62–20.44 s (3.8 s)
Drills tab tap at 16.62: `Saved drills` title with the bookmark-add action, list:
`El Presidente` — Standard mode · Random delay; `Bill Drill` — Standard mode · Fixed 2.0s
delay; `Draw drill` — Par mode · Random delay · Par 1.5s × 5; `Stage warm-up` — Stage mode
· Random delay · Stage 60s (checked, because Settings is on Stage 60s). Tap `Bill Drill`
at 17.71 (strong): the check moves to it, and the snackbar `Applied “Bill Drill”` (white
on black) rises above the tab bar. Hold. Settings tab tap at 20.44 (strong) shows the
proof: Standard selected, START DELAY now `Fixed` with `Fixed delay 2.0s`.
Caption 16.72–20.30: SAVE YOUR DRILLS. / Name it once. Load it in one tap.
Interaction: tab tap, row tap, snackbar, tab tap
Audio: selection tick on tab taps, click on the row, light glass tick with the snackbar
Transition mood: tab cut → Scene 6

### Scene 6 — Dial in the mic — 20.44–25.95 s (5.5 s incl. 1.6 s navigation)
Shot detection row tap at 20.98 pushes the `Shot detection` page (`Test microphone` /
`Auto-configure` rows, Sensitivity, Echo filter, Frequency band filter). Test microphone
tap at 22.07 (strong) pushes `Test microphone`: instruction, MIC meter with the red
threshold line at 85 %, Peak hold / Threshold, Dominant Hz, Play test beep, Sensitivity
slider, tip. Shot peaks at 23.16 and 24.26 (both strong) cross the line; the slider
drags 15 % → 25 % at 24.79–25.39 and the red line moves to 75 %.
Caption 22.17–25.75: DIAL IN THE MIC. / Live level meter · Your threshold
Phone drops out 25.95–26.40.
Audio: soft drops on the two pushes, two steel pings, slider click
Transition mood: dramatic → Scene 7

### Scene 7 — Outro — 26.97–29.90 s (2.9 s)
App icon + SIMPLE SHOT / TIMER slam in at 26.97 (strong). 27.60: `Free on Google Play`.
28.00: `Offline · No account · 5 languages`. Par beep at 29.10; music fades out; hold to 29.90.
Audio: impact bell on the slam, par beep last

**Music mood for this video:** steady and confident
**Audio summary:** A voice in silence, then the real beep kicks off a steady bed that
carries shot pings, taps and page drops, and ends on the app's own par beep.

## Fictional data on screen
Drill names, the label "El Presidente dry run", shot times and the 9:41 clock are made up.
No real user data appears.
