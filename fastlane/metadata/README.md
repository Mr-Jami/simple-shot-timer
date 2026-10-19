# Store listing text

The text of the Google Play and App Store listings, in every language the app
supports. The stores hold the live copy; this folder is where it is written and
kept in sync with the app. Screenshots and the feature graphic are in
[`branding/store-listing/`](../../branding/store-listing/README.md).

Last updated: 2026-10-19, app 2.3.0.

The layout is the one fastlane uses (`supply` reads `android/`, `deliver` reads
`ios/` with `metadata_path: fastlane/metadata/ios`), and F-Droid reads
`android/` too, so the files can be uploaded by a tool later. Until then they
are pasted by hand: open a file, use GitHub's *Raw* view and copy everything.

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

The folder names are the store's own locale codes. The Spanish and French text
also suits Latin America and Canada: to cover them, add Spanish (Latin America)
`es-419` and French (Canada) `fr-CA` on Play, Spanish (Mexico) and French
(Canada) in App Store Connect, with the same text. The Portuguese is Brazilian,
like the app.

## Fields

| File | Store field | Limit |
|---|---|---|
| `android/*/title.txt` | Play: App name | 30 |
| `android/*/short_description.txt` | Play: Short description | 80 |
| `android/*/full_description.txt` | Play: Full description | 4000 |
| `ios/*/name.txt` | App Store: Name | 30 |
| `ios/*/subtitle.txt` | App Store: Subtitle | 30 |
| `ios/*/description.txt` | App Store: Description | 4000 |
| `ios/*/keywords.txt` | App Store: Keywords, comma-separated | 100 |
| `ios/*/release_notes.txt` | App Store: What's New in This Version | 4000 |

`ios/en-US` has no `keywords.txt`: the English keywords live only in App Store
Connect. Promotional text isn't kept here either.

The Play "What's new" text is generated from the GitHub Release
(`.github/scripts/play_release_notes.py`) and is English only; Play shows it in
every language.

## Where to paste

**Google Play**: Play Console → *Grow users → Store presence → Store
listings*. The default listing is English. *Manage translations → Add your own
translations*, pick the languages, then fill in app name, short and full
description for each. Graphics fall back to the default listing.

**App Store**: App Store Connect → the app.

- *App Information*: add each language (the language menu at the top right),
  then fill in **Name**, **Subtitle** and **Privacy Policy URL**. The
  privacy URL is `https://simpleshottimer.com/de/datenschutz/` for German and
  `https://simpleshottimer.com/privacy/` for every other language, the same
  pages the app opens.
- *The version being prepared* (2.3.0): for each language fill in
  **Description**, **Keywords**, **What's New**, **Support URL**
  (`https://jami-it.de/en/#contact`, as in English) and **Marketing URL**
  (`https://simpleshottimer.com/`, `https://simpleshottimer.com/de/` for
  German). Screenshots fall back to English.

The description, keywords and What's New can only change with a new version;
name and subtitle change with the next submission.

## Writing and translating

- The Play and App Store descriptions are the same text with platform
  details swapped: the iPhone mic, the Files app, "volume" instead of "media
  volume", no Material 3, and no permissions section on the App Store. Change
  both together, in every language.
- When a feature changes, update English first, then each language, then the
  README features, the website homepages and `website/public/llms.txt`.
- Use the app's own words for anything on screen (`assets/i18n/<code>.json`):
  button labels such as STOPP, LOPETA or PARAR, mode names, Settings items.
- Par, Stage and Split stay in English, as in the app and in IPSC.
- German uses *du* and says "Beep", like the website. French uses *vous*,
  Russian *вы*; Spanish, Polish, Portuguese and Finnish address the reader
  informally, as the app does.
- Keep "Simple Shot Timer" untranslated. Don't call it the first or only free
  shot timer.
- Check the limits after editing: every file must fit the table above.
