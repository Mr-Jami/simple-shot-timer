# Launch video

The 30-second vertical launch video for Simple Shot Timer (Play Store listing,
social posts). It is rendered from an HTML composition with
[Hyperframes](https://www.npmjs.com/package/hyperframes); the storyboard and
the composition are tracked here, the media is not.

Current cut: 2026-10-01, app 2.0 UI (four-tab shell, saved drills), 1080x1920,
29.9 s. The first cut (2026-09-24, 1.6 UI, 25 s) is kept locally only.

## What is tracked

| File | Purpose |
|---|---|
| `storyboard.md` | Storyboard: scenes, timings, captions, beat locks, audio plan |
| `brief.md` | Hand-off brief: what must appear on screen, visual identity, audio |
| `composition/index.html` | The video itself: recreated app screens, GSAP timeline, audio clips |
| `composition/assets/music-rms.js` | Per-frame loudness of the music bed (drives the glow); derived, 4 KB |
| `share-copy.txt` | Caption for the post |

## What is not tracked, and where it comes from

Everything under `composition/assets/` except `music-rms.js` is ignored. Put
these files in place before rendering.

| Path under `composition/assets/` | What | Source |
|---|---|---|
| `fonts/Roboto.ttf` | Roboto variable font | Google Fonts (free licence) |
| `img/icon.png` | App icon | Copy of `assets/branding/icon.png` in this repo |
| `music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` | Music bed, 110 BPM | Ships with the `brag` Claude Code plugin (`skills/brag/assets/music/`) |
| `sfx/click_001.ogg`, `sfx/drop_001.ogg`, `sfx/drop_002.ogg`, `sfx/select_008.ogg` | Tap and page sounds | `brag` plugin, `assets/sfx/interface/` (Kenney, CC0) |
| `sfx/click2.ogg` | Slider tick | `brag` plugin, `assets/sfx/ui/` (CC0) |
| `sfx/impactGlass_light_001.ogg`, `sfx/impactBell_heavy_000.ogg` | Snackbar tick, logo hit | `brag` plugin, `assets/sfx/impact/` (CC0) |
| `sfx/start-beep.wav`, `sfx/par-beep.wav` | The app's own beeps | Generate, see below |
| `sfx/shot-1.wav` to `sfx/shot-5.wav` | Steel-plate pings standing in for shots | Maintainer's local `brag-assets/shots/`, built from the plugin's metal and plate impact SFX |
| `sfx/ro-are-you-ready.wav`, `sfx/ro-standby.wav` | Range Officer voice for the cold open | Maintainer's local `brag-assets/`, two short cuts from a range-commands recording. Not redistributable; see the RO section of the plan for recording your own |

No gunshot audio is used anywhere: steel pings keep the video safe to post on
platforms that restrict gunfire sounds.

### Generating the beeps

Same tone as `AudioService`: 2325 Hz sine, 300 ms (start) and 700 ms (par),
8 ms attack, 20 ms release. The files below are 48 kHz 16-bit mono with
ffmpeg's default linear fades; the app synthesises the beep at 44.1 kHz with
raised-cosine ramps.

```sh
ffmpeg -f lavfi -i "sine=frequency=2325:sample_rate=48000:duration=0.3" \
  -af "afade=t=in:st=0:d=0.008,afade=t=out:st=0.28:d=0.02" -ac 1 -c:a pcm_s16le \
  composition/assets/sfx/start-beep.wav
ffmpeg -f lavfi -i "sine=frequency=2325:sample_rate=48000:duration=0.7" \
  -af "afade=t=in:st=0:d=0.008,afade=t=out:st=0.68:d=0.02" -ac 1 -c:a pcm_s16le \
  composition/assets/sfx/par-beep.wav
```

### Regenerating `music-rms.js` (only if the music or its length changes)

The bed starts at 4.6 s (the start beep) and runs 25.3 s. The extraction helper
ships with the `hyperframes-creative` skill and needs Python with numpy.

```sh
ffmpeg -ss 0 -t 25.3 -i composition/assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3 \
  -ac 1 -ar 44100 work/music-seg.wav
python <skills>/hyperframes-creative/scripts/extract-audio-data.py work/music-seg.wav --fps 30 --bands 8 -o work/audio-data.json
# write composition/assets/music-rms.js as: window.MUSIC_RMS=[<rms of each frame, 3 decimals>];
```

## Rendering

```sh
cd composition
npx hyperframes check                                   # must report 0 errors
npx hyperframes render --quality high --workers 2 --output ../brag.mp4
cd ..
# poster: the settled "HEARS EVERY SHOT." frame, then baked in as frame 0 so every
# platform shows it as the idle thumbnail
ffmpeg -ss 8.8 -i brag.mp4 -frames:v 1 -q:v 2 brag.jpg
ffmpeg -y -i brag.mp4 -i brag.jpg -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" \
  -map "[v]" -map 0:a? -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a copy \
  -movflags +faststart brag.poster.mp4 && mv brag.poster.mp4 brag.mp4
```

`brag.mp4` and `brag.jpg` land in this folder and are ignored by git.

## How the composition is built

- The phone screen is the app recreated in HTML at 390x845 dp and scaled 1.641x into
  a phone frame; nothing is a screenshot. Colours, type sizes and spacing follow
  `lib/theme/app_theme.dart` and the screen widgets. When the UI changes, edit the
  matching block in `composition/index.html` (each screen is a commented section).
- Strings on screen come from `assets/i18n/en.json`; keep them verbatim.
- Timing is one paused GSAP timeline. Composition time = music track time + 4.6 s.
  Taps and reveals sit on the track's beat grid (0.5455 s); the strong cues used are
  listed in `storyboard.md`. Per-frame values (timer, mic meters, glow) are computed in
  `render(t)` so every frame is a pure function of time.
- Two Hyperframes 0.8.99 rules worth knowing: a pushed page is opaque, so the layer
  under it is hidden with `autoAlpha:0` once the slide finishes (otherwise `check`
  reports the covered text as overlapping), and ripple tweens use
  `immediateRender:false` so their start state is not drawn before the tap.
- The 25 s guideline of the `brag` plugin is exceeded on purpose: the drills scene and
  the real navigation steps of the 2.0 UI added about 5 s to the 2026-09-24 cut.

## Facts shown on screen

Drill names, the string label, shot times and the 9:41 clock are made up. No real
user data appears in the video.
