# Wikidata item (draft)

A Wikidata item tells search engines and AI assistants what Simple Shot Timer
is, as structured facts: a free, open-source mobile app for Android and iOS,
used for practical shooting and dry fire, with its website, source code and
store IDs. Google's Knowledge Graph and most AI models draw on Wikidata.

Checked on 2026-10-19: Wikidata has no item for Simple Shot Timer, Tareq Jami
or Jami IT yet. Every item and property ID below was looked up through the
Wikidata API; [AntennaPod](https://www.wikidata.org/wiki/Q16927599), an
open-source app with a mature item, served as the model.

## Creating it

The quickest way is the batch in
[`wikidata-quickstatements.tsv`](wikidata-quickstatements.tsv): it creates
the item with every label, description, statement and reference in one go.

1. Sign in to Wikidata with a Wikimedia account (create one if needed).
2. Open <https://quickstatements.toolforge.org/>, sign in there too
   ("Log in" authorises the tool through Wikimedia).
3. *New batch* → paste the file's contents (open the file's *Raw* view and
   copy everything, so the tabs survive) → *Import V1 commands* → check the
   preview → *Run*.
4. Note the new item ID (Q…).

To create it by hand instead, use *Create a new Item* on Wikidata with the
label and description below, then add the statements one by one.

Wikidata accepts an item like this because the app is a clearly identifiable
entity described by public sources (the store listings, the repository, the
website). Keep it factual: no promotional wording, and a reference on every
statement that isn't itself a URL. Editing about your own project is allowed;
stick to facts the sources show.

## What the item says

**Label**: Simple Shot Timer (en, de).

**Descriptions** (lower case, no article, as Wikidata wants them):

| Language | Description |
|---|---|
| en | free and open-source shot timer app for Android and iOS |
| de | freie Open-Source-Shot-Timer-App für Android und iOS |
| es | aplicación de cronómetro de tiro libre y de código abierto para Android e iOS |
| fr | application libre et open source de chronomètre de tir pour Android et iOS |
| pl | wolna aplikacja timera strzeleckiego o otwartym kodzie dla Androida i iOS |
| pt-br | aplicativo livre e de código aberto de timer de tiro para Android e iOS |
| fi | vapaa ja avoimen lähdekoodin ajanottosovellus ammuntaan Androidille ja iOS:lle |
| ru | свободное приложение-таймер для стрельбы с открытым исходным кодом для Android и iOS |

**Statements**:

| Property | Value | Qualifiers | Reference |
|---|---|---|---|
| instance of (P31) | mobile app (Q620615) | | Play listing |
| instance of (P31) | free software (Q341) | | repository |
| copyright license (P275) | GNU GPL, version 3.0 (Q10513445) | | LICENSE |
| copyright status (P6216) | copyrighted (Q50423863) | | NOTICE |
| operating system (P306) | Android (Q94), iOS (Q48493) | | store listings |
| platform (P400) | Android (Q94), iOS (Q48493) | | store listings |
| programmed in (P277) | Dart (Q406009) | | repository |
| depends on software (P1547) | Flutter (Q39072787) | | repository |
| distributed by (P750) | Google Play (Q79576), App Store (Q368215) | | store listings |
| distribution format (P437) | digital download (Q54820071) | | Play listing |
| Google Play Store app ID (P3418) | cc.jami.simpleshottimer | | Play listing |
| App Store app ID (P3861) | 6819042653 | | App Store listing |
| official website (P856) | https://simpleshottimer.com/ | language: English (Q1860) | |
| official website (P856) | https://simpleshottimer.com/de/ | language: German (Q188) | |
| source code repository URL (P1324) | https://github.com/Mr-Jami/simple-shot-timer | web interface: GitHub (Q364); version control: Git (Q186055) | |
| issue tracker URL (P1401) | https://github.com/Mr-Jami/simple-shot-timer/issues | | |
| language of work or name (P407) | English, German, Spanish, Finnish, French, Polish, Brazilian Portuguese, Russian | | assets/i18n |
| has use (P366) | practical shooting (Q2502572), dry fire (Q5309588) | | website |
| inception (P571) | 14 May 2026 (v1.0.0) | | v1.0.0 release |
| software version identifier (P348) | 2.3.1 | version type: stable version (Q2804309); publication date: 19 October 2026 | v2.3.1 release |

Each reference is a *reference URL* (P854) with *retrieved* (P813)
2026-10-19.

## Left out on purpose

- **Developer (P178)** needs an item for the developer. Neither Tareq Jami
  nor Jami IT has one, and creating items for yourself mostly gets them
  deleted unless they meet Wikidata's notability on their own. Add it later if
  such an item appears.
- **Logo (P154) and image (P18)** must be files on Wikimedia Commons under a
  free license. The icon and logo are reserved (NOTICE, term 3), so they can't
  go there. A plain screenshot of the app could, if you want one.
- **"instance of: shot timer" (Q30715299)**: that item describes the hardware
  device, so the app is described through *has use* instead.

## After it exists

- Add the item to `sameAs` in the JSON-LD of both homepages
  (`https://www.wikidata.org/wiki/Q…`), and to `website/public/llms.txt`.
- Once F-Droid has the app, add *F-Droid package* (P3597):
  `cc.jami.simpleshottimer` and *distributed by* F-Droid (Q1386210).
- On a new release, add a *software version identifier* statement for it,
  mark it as preferred rank and set the previous one to normal (that is how
  Wikidata shows the current version), or let a bot do it; it is optional.
