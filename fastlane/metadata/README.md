# Store listing text

The text of the Google Play and App Store listings, in every language the app
supports. This folder is the source: the *Update store listings* workflow
(`.github/workflows/update-store-listings.yml`, see the main README) uploads
it to both stores. Screenshots and the feature graphic are in
[`branding/store-listing/`](../../branding/store-listing/README.md).

Last updated: 2026-10-19, app 2.3.1. The App Store is still on 2.1.0, so What's New covers 2.2.0 and 2.3.0 as well.

The layout is fastlane's: `supply` reads `android/`, `deliver` reads `ios/`.
F-Droid reads `android/` too.

## Languages

| Language | Google Play | App Store Connect |
|---|---|---|
| English (default) | `android/en-US` | `ios/en-US` |
| German | `android/de-DE` | `ios/de-DE` |
| Spanish | `android/es-ES` | `ios/es-ES` |
| Finnish | `android/fi-FI` | `ios/fi` |
| French | `android/fr-FR` | `ios/fr-FR` |
| Polish | `android/pl-PL` | `ios/pl` |
| Portuguese (Brazil) | `android/pt-BR` | `ios/pt-BR` |
| Russian | `android/ru-RU` | `ios/ru` |

The folder names are the stores' own locale codes, and the workflow uploads
every folder it finds. The Spanish and French text also suits Latin America
and Canada: copying `es-ES` to `es-419` (Play) and `es-MX` (App Store), and
`fr-FR` to `fr-CA` (both), would add those listings. The Portuguese is
Brazilian, like the app.

## Fields

| File | Store field | Limit |
|---|---|---|
| `android/*/title.txt` | Play: App name | 30 |
| `android/*/short_description.txt` | Play: Short description | 80 |
| `android/*/full_description.txt` | Play: Full description | 4000 |
| `ios/*/name.txt` | App Store: Name | 30 |
| `ios/*/subtitle.txt` | App Store: Subtitle | 30 |
| `ios/*/privacy_url.txt` | App Store: Privacy Policy URL | |
| `ios/*/description.txt` | App Store: Description | 4000 |
| `ios/*/keywords.txt` | App Store: Keywords, comma-separated | 100 |
| `ios/*/release_notes.txt` | App Store: What's New in This Version | 4000 |
| `ios/*/support_url.txt` | App Store: Support URL | |
| `ios/*/marketing_url.txt` | App Store: Marketing URL | |

Name, subtitle and privacy URL belong to the app (*App Information*); the
rest belongs to the version being prepared, so description, keywords and
What's New can only change with a new version. The privacy URL is the page
the app itself opens: `/de/datenschutz/` for German, `/privacy/` for every
other language.

`ios/en-US` has no `keywords.txt`: the English keywords live only in App Store
Connect, and the workflow leaves fields without a file alone. Promotional
text isn't kept here either.

The Play "What's new" text is generated from the GitHub Release
(`.github/scripts/play_release_notes.py`) and is English only; Play shows it in
every language.

`test/store_listing_test.dart` checks every file against these limits and
fails when an app language has no folder in either store.

## By hand

Without the workflow, open a file in GitHub's *Raw* view, copy everything and
paste it into the field:

- **Google Play**: Play Console → *Grow users → Store presence → Store
  listings*. *Manage translations → Add your own translations* adds a
  language. Graphics fall back to the default (English) listing.
- **App Store**: App Store Connect → the app. Add a language with the
  language menu on *App Information* (name, subtitle, privacy URL) and fill in
  the rest on the version being prepared. Screenshots fall back to English.

## Writing and translating

- The Play and App Store descriptions are the same text with platform
  details swapped: the iPhone mic, the Files app, "volume" instead of "media
  volume", no Material 3, and no permissions section on the App Store. Change
  both together, in every language.
- When a feature changes, update English first, then each language, then the
  README features, the website homepages and `website/public/llms.txt`.
- Each release needs What's New in every language in `ios/*/release_notes.txt`
  before the App Store run.
- Use the app's own words for anything on screen (`assets/i18n/<code>.json`):
  button labels such as STOPP, LOPETA or PARAR, mode names, Settings items.
- Par, Stage and Split stay in English, as in the app and in IPSC.
- German uses *du* and says "Beep", like the website. French uses *vous*,
  Russian *вы*; Spanish, Polish, Portuguese and Finnish address the reader
  informally, as the app does.
- Keep "Simple Shot Timer" untranslated. Don't call it the first or only free
  shot timer.
