# simpleshottimer.com

The homepage for Simple Shot Timer, in English and German: a static site built with
[Vite](https://vite.dev) and animated with [Anime.js](https://animejs.com) 4. Netlify
builds and deploys it through its GitHub integration, configured in `../netlify.toml`.

The hero phone is a playable timer: press START, wait for the app's 2325 Hz beep,
and a simulated five-shot string comes in with realistic splits. The other
phones show the app's screens recreated in HTML, with the same markup and colours as
`branding/store-listing/index.html` and the app's own strings in each language.

The site loads nothing from third parties: fonts (Inter, Roboto, Montserrat) are
bundled from `@fontsource`, and there are no cookies, analytics or embeds. The demo
never uses the microphone, and `_headers` denies it (`microphone=()`).

## Local development

```sh
cd website
npm install
npm run dev       # http://localhost:5173 (German: /de/)
npm run build     # writes dist/
npm run preview   # serves dist/
```

## Pages

| English | German | Source |
| --- | --- | --- |
| `/` | `/de/` | `index.html`, `de/index.html` |
| `/changelog/` | `/de/changelog/` | built from the repository's `CHANGELOG.md` |
| `/privacy/` (app) | `/de/datenschutz/` | the app's privacy policy |
| `/privacy/website/` | `/de/datenschutz/website/` | the website's privacy policy |
| `/imprint/` | `/de/impressum/` | imprint, linked to Jami IT |

The German privacy policies and imprint are the legally binding versions. Unknown
paths get `404.html`, or `de/404.html` under `/de/` (see `public/_redirects`).

## Layout

```
website/
├── index.html, de/index.html   # the homepages: copy, SEO tags, demo and section markup
├── changelog/, privacy/, imprint/, de/...   # the other pages (see the table above)
├── 404.html, de/404.html
├── build/                # runs at build time, not in the browser
│   ├── site.js           # page list, nav + footer + hreflang for both languages, sitemap
│   ├── changelog.js      # CHANGELOG.md -> changelog pages (same rewrite as the Play notes)
│   ├── sprite.html       # the icon sprite the homepages use
│   └── llms-full.txt     # template for /llms-full.txt (the changelog is filled in)
├── src/
│   ├── main.js           # homepage script: demo and motion (other pages need no JS)
│   ├── i18n.js           # EN/DE strings for the phones and the demo hints
│   ├── demo.js           # the playable hero timer (Web Audio beep, simulated string)
│   ├── screens.js        # app screens as HTML strings
│   ├── motion.js         # all Anime.js motion: intro, reveals, sticky story, bento, FAQ
│   ├── halftone.js       # the store listing's halftone dots, drawn on a canvas
│   └── styles/           # site.css (page) and app-ui.css (the app, scoped to .app);
│                         # they @import the bundled fonts
├── public/               # copied as-is: _headers, _redirects, icons, og images,
│                         # robots.txt, llms.txt
└── og-image/index.html   # source of public/og.png and og-de.png (not part of the build)
```

Every page loads its stylesheets with `<link rel="stylesheet">` in the `<head>`, never
from JavaScript: a stylesheet imported from JS arrives after the first paint, which
shows one unstyled frame on every load. Inline SVGs also carry `width`/`height`
attributes, so they stay small even before CSS applies.

Pages hold `<!--site:...-->` placeholders (`nav`, `footer`, `alternates`, `sprite`,
`changelog`) that the plugin in `vite.config.js` fills in from `build/`. So the
navigation, the language switch, the footer and the canonical/hreflang links are
written once for both languages. The build fails if a placeholder is left unfilled,
in the pages and in `llms-full.txt`.

### Adding a page

1. Add the English/German URL pair to `PAGES` in `build/site.js`.
2. Create both `index.html` files (copy `imprint/index.html` and
   `de/impressum/index.html`). The page joins the build, the sitemap and the language
   switch automatically.
3. If the footer should link to it, add it to `footer()` in `build/site.js`.

## Changelog

`/changelog/` and `/de/changelog/` are generated from `../CHANGELOG.md`, which
release-please writes. Entries are rewritten for app users with the same rules as
`.github/scripts/play_release_notes.py` (no scopes, links or commit hashes; only
*Changed*, *New*, *Fixes* and *Improvements*). The German page translates the headings;
the entries stay in English. The footer version, the changelog's `lastmod` in
`sitemap.xml` and the release list in `llms-full.txt` come from the same file.
Only `## x.y.z` headings count as releases, so a hand-added `## Unreleased` is
skipped. If no release can be parsed, the build fails instead of deploying an empty
changelog.

Netlify also builds when `CHANGELOG.md` changes on `main` (see the `ignore` rule in
`../netlify.toml`), so merging a release PR republishes the site with the new version.
Nobody has to touch `website/`.

## Motion

Motion follows Apple's guidance for fluid interfaces:

- Critically damped springs (`spring({ bounce: 0 })`) for everything that moves.
  Nothing overshoots.
- Every animation starts from the element's current value, so it can be interrupted
  and reversed mid-flight (the FAQ panels, the demo's review page, the sticky story
  screens). Large moves use `transform` and `opacity` only.
- Screens in the sticky story enter from the direction you scroll and leave the other
  way. The demo's review page slides in from the right and leaves to the right.
- The beep, the screen flash and the haptic fire on the same frame.
- With `prefers-reduced-motion`, movement becomes cross-fades, the beep flash
  becomes an edge ring (as in the app), and the looping visuals hold still.
  `prefers-reduced-transparency` and `prefers-contrast` make the navigation bar solid.

## Deployment

Netlify's GitHub integration builds and deploys the site; `../netlify.toml` holds the
settings (base `website`, `npm run build`, publish `dist`, Node 22). Pushes to `main`
go to production. Every pull request gets a deploy preview, and the Netlify bot links it
in a PR comment. The `ignore` rule skips builds for commits that change neither
`website/` nor `CHANGELOG.md`, so app-only commits cost no build minutes.

### One-time setup

1. **Import the repository**: in Netlify, *Add new project → Import an existing
   project → GitHub*, authorise the Netlify app for `Mr-Jami/simple-shot-timer`, pick the
   repository and keep `main` as the branch to deploy. The build settings are read from
   `netlify.toml`, so the fields can stay as Netlify fills them in. Select *Deploy*.
2. **Name the project** (optional): *Project configuration → General → Project
   information → Change project name*, for example `simpleshottimer`. This only changes
   the `*.netlify.app` address.
3. **Connect the domain**: in Netlify, *Domain management → Add a domain*, enter
   `simpleshottimer.com` and make it the primary domain (`www` then redirects to it).
   Netlify recommends Netlify DNS for an apex domain: change the nameservers at the
   registrar to the four Netlify shows. With DNS kept at the registrar instead, add an
   `A` record for `@` pointing to `75.2.60.5` and a `CNAME` for `www` pointing to
   `<site>.netlify.app`. Netlify issues the HTTPS certificate once DNS resolves.

## Maintenance notes

- **Copy in two languages**: homepage text lives in `index.html` and `de/index.html`;
  text that scripts write (the phones, the demo hints) lives in `src/i18n.js`, whose
  app strings are copied from `assets/i18n/en.json` and `de.json`. Change both
  languages together.
- **Security headers** live in `public/_headers`. The CSP allows the one inline script
  in both homepages by its SHA-256 hash. If you change that line, recompute the hash:
  `printf "%s" "document.documentElement.classList.add('js')" | openssl dgst -sha256 -binary | openssl base64`
- **When the iPhone app is live**: in both homepages, replace "iPhone soon" in the hero
  pill, the coming-soon box in `#download` (with Apple's *Download on the App Store*
  badge), the iPhone answer in the FAQ, and add `"iOS"` to `operatingSystem` in the
  JSON-LD. Update `public/llms.txt` and `build/llms-full.txt` too.
- **Link preview images**: `public/og.png` and `public/og-de.png` are screenshots of
  `#og` in `og-image/index.html` at 1200x630. Run `npm run dev`, open
  `http://localhost:5173/og-image/` (add `?lang=de` for the German one), and capture
  `#og` at CSS scale 1 (for example with Playwright:
  `page.locator('#og').screenshot({ path: 'public/og.png' })`).
- **App screens**: after a UI change in the app, update `src/screens.js` (and the
  store listing, which shares the markup).
- **Privacy policies and imprint**: the app policy (`/privacy/`, `/de/datenschutz/`)
  and the website policy (`/privacy/website/`, `/de/datenschutz/website/`) are
  separate. Change each language pair together and update the date at the top. The
  store listings (Play Console, App Store Connect) should point to
  `https://simpleshottimer.com/privacy/`.
- **llms.txt** (`public/`) is hand-written; `llms-full.txt` comes from
  `build/llms-full.txt` plus the changelog. When the homepage copy or the FAQ
  changes, update both.
- **Commits**: `website/` is excluded from release-please (`exclude-paths` in
  `release-please-config.json`), so site changes never bump the app version or reach
  the store release notes. Use `docs(website):` or `chore(website):` anyway.
