// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// Strings for the text that scripts put on the page: the recreated app screens
// and the demo's hints. App strings are copied from assets/i18n/{en,de}.json so
// the phones read like the real app in each language.
export const LANG = document.documentElement.lang.startsWith('de') ? 'de' : 'en';
export const LOCALE = LANG === 'de' ? 'de-DE' : 'en-US';

const STRINGS = {
  en: {
    // nav.*
    'nav.timer': 'Timer', 'nav.drills': 'Drills', 'nav.history': 'History', 'nav.settings': 'Settings',
    // home.*
    'home.ready': 'Ready',
    'home.pressStartToBegin': 'Press START to begin',
    'home.standBy': 'STAND BY',
    'home.time': 'TIME', 'home.last': 'LAST', 'home.total': 'TOTAL',
    'home.noShotsDetected': 'No shots detected',
    'home.noShotsHint': 'Nothing was saved. Adjust sensitivity or add a shot by hand.',
    'home.lastString': 'Last {seconds}s · {count} shots',
    'home.lastStringOne': 'Last {seconds}s · 1 shot',
    'home.review': 'Review', 'home.addShot': 'Add shot',
    'home.savedAt': 'Saved {time}',
    'home.stat.shots': 'SHOTS', 'home.stat.first': 'FIRST', 'home.stat.split': 'SPLIT',
    'home.start': 'START', 'home.stop': 'STOP',
    'home.modeChip': '{mode} mode',
    'home.delayInstant': 'Instant start',
    'home.delayFixed': 'Fixed {seconds}s delay',
    'home.delayRandom': 'Random delay',
    // enums
    'mode.standard': 'Standard', 'mode.par': 'Par', 'mode.stage': 'Stage',
    'delay.instant': 'Instant', 'delay.fixed': 'Fixed', 'delay.random': 'Random',
    // history / review / drills / settings
    'history.title': 'History',
    'history.itemFallback': '{seconds}s · {count} shots',
    'history.itemFallbackOne': '{seconds}s · 1 shot',
    'review.title': 'Review', 'review.label': 'Label', 'review.notes': 'Notes',
    'review.penalty': 'Penalty: {seconds}s',
    'review.shotsHeader': 'Shots ({count})',
    'review.add': 'Add',
    'review.splitFirst': 'first', 'review.splitOther': 'split {seconds}s',
    'review.headerLine': '{drill} · {delay} ({seconds}s delay)',
    'review.summary.total': 'TOTAL', 'review.summary.first': 'FIRST', 'review.summary.fastest': 'FASTEST',
    'review.summary.slowest': 'SLOWEST', 'review.summary.average': 'AVERAGE', 'review.summary.shots': 'SHOTS',
    'drills.manageTitle': 'Saved drills',
    'drills.appliedSnack': 'Applied “{name}”',
    'settings.title': 'Settings',
    'settings.section.drillMode': 'Drill mode', 'settings.section.startDelay': 'Start delay', 'settings.section.beep': 'Beep',
    'settings.randomMin': 'Random min', 'settings.randomMax': 'Random max',
    'settings.volume': 'Volume', 'settings.visualFlash': 'Visual flash on beep', 'settings.hapticOnBeep': 'Haptic on beep',
    // Site: the demo
    'demo.startLabel': 'Start timer', 'demo.stopLabel': 'Stop timer', 'demo.backLabel': 'Back',
    'demo.standby': 'Stand by… wait for the beep.',
    'demo.goTap': 'Go! Tap the screen or press <b>Space</b> for every shot.',
    'demo.goClap': 'Go! Clap for every shot.',
    'demo.keepGoing': 'Keep going, then press <b>STOP</b>.',
    'demo.cancelled': 'Cancelled. Press <b>START</b> when you’re ready.',
    'demo.noShots': 'No shots that time. Press <b>START</b>, then tap after the beep.',
    'demo.done': '{shots} in {total}s. Open <b>Review</b> for every split, or press <b>START</b> to go again.',
    'demo.review': 'Every shot with its split. Use the back arrow to return.',
    'demo.again': 'Press <b>START</b> to go again.',
    'demo.notYet': 'Not yet: wait for the beep.',
    'demo.addShotSnack': 'In the app, you can type in a shot the mic missed.',
    'demo.micUnavailable': 'This browser can’t use the microphone here. Tap the screen instead.',
    'demo.micDenied': 'No microphone access. Tap the screen or press <b>Space</b> instead.',
    'demo.micOn': 'Mic on. Press <b>START</b>, then clap after the beep. Audio stays in your browser.',
    'demo.micOnRunning': 'Clap for every shot.',
    'demo.micListening': 'Listening for claps',
    'demo.micOff': 'Clap to fire',
    'demo.shotOne': '1 shot', 'demo.shotMany': '{count} shots',
  },
  de: {
    'nav.timer': 'Timer', 'nav.drills': 'Drills', 'nav.history': 'Verlauf', 'nav.settings': 'Einstellungen',
    'home.ready': 'Bereit',
    'home.pressStartToBegin': 'START drücken, um zu beginnen',
    'home.standBy': 'BEREITHALTEN',
    'home.time': 'ZEIT', 'home.last': 'LETZTER', 'home.total': 'GESAMT',
    'home.noShotsDetected': 'Keine Schüsse erkannt',
    'home.noShotsHint': 'Nichts gespeichert. Empfindlichkeit anpassen oder Schuss manuell hinzufügen.',
    'home.lastString': 'Zuletzt {seconds}s · {count} Schüsse',
    'home.lastStringOne': 'Zuletzt {seconds}s · 1 Schuss',
    'home.review': 'Auswerten', 'home.addShot': 'Schuss hinzufügen',
    'home.savedAt': 'Gespeichert {time}',
    'home.stat.shots': 'SCHÜSSE', 'home.stat.first': 'ERSTER', 'home.stat.split': 'SPLIT',
    'home.start': 'START', 'home.stop': 'STOPP',
    'home.modeChip': 'Modus: {mode}',
    'home.delayInstant': 'Sofortstart',
    'home.delayFixed': 'Feste Verzögerung {seconds}s',
    'home.delayRandom': 'Zufällige Verzögerung',
    'mode.standard': 'Standard', 'mode.par': 'Par', 'mode.stage': 'Stage',
    'delay.instant': 'Sofort', 'delay.fixed': 'Fest', 'delay.random': 'Zufällig',
    'history.title': 'Verlauf',
    'history.itemFallback': '{seconds}s · {count} Schüsse',
    'history.itemFallbackOne': '{seconds}s · 1 Schuss',
    'review.title': 'Auswertung', 'review.label': 'Bezeichnung', 'review.notes': 'Notizen',
    'review.penalty': 'Strafzeit: {seconds}s',
    'review.shotsHeader': 'Schüsse ({count})',
    'review.add': 'Hinzufügen',
    'review.splitFirst': 'erster', 'review.splitOther': 'Split {seconds}s',
    'review.headerLine': '{drill} · {delay} ({seconds}s Verzögerung)',
    'review.summary.total': 'GESAMT', 'review.summary.first': 'ERSTER', 'review.summary.fastest': 'SCHNELLSTE',
    'review.summary.slowest': 'LANGSAMSTE', 'review.summary.average': 'DURCHSCHNITT', 'review.summary.shots': 'SCHÜSSE',
    'drills.manageTitle': 'Gespeicherte Drills',
    'drills.appliedSnack': '„{name}“ angewendet',
    'settings.title': 'Einstellungen',
    'settings.section.drillMode': 'Modus', 'settings.section.startDelay': 'Startverzögerung', 'settings.section.beep': 'Signalton',
    'settings.randomMin': 'Zufall min', 'settings.randomMax': 'Zufall max',
    'settings.volume': 'Lautstärke', 'settings.visualFlash': 'Bildschirm-Blitz beim Ton', 'settings.hapticOnBeep': 'Vibration beim Ton',
    'demo.startLabel': 'Timer starten', 'demo.stopLabel': 'Timer stoppen', 'demo.backLabel': 'Zurück',
    'demo.standby': 'Bereithalten … warte auf den Beep.',
    'demo.goTap': 'Los! Tippe für jeden Schuss auf den Bildschirm oder drück die <b>Leertaste</b>.',
    'demo.goClap': 'Los! Klatsch für jeden Schuss.',
    'demo.keepGoing': 'Weiter so, dann <b>STOPP</b> drücken.',
    'demo.cancelled': 'Abgebrochen. Drück <b>START</b>, wenn du bereit bist.',
    'demo.noShots': 'Diesmal keine Schüsse. Drück <b>START</b> und tippe nach dem Beep.',
    'demo.done': '{shots} in {total}s. Unter <b>Auswerten</b> siehst du jeden Split, mit <b>START</b> geht es von vorn los.',
    'demo.review': 'Jeder Schuss mit seinem Split. Mit dem Pfeil oben geht es zurück.',
    'demo.again': 'Mit <b>START</b> geht es von vorn los.',
    'demo.notYet': 'Noch nicht: warte auf den Beep.',
    'demo.addShotSnack': 'In der App kannst du einen Schuss eintippen, den das Mikrofon verpasst hat.',
    'demo.micUnavailable': 'Dieser Browser kann hier kein Mikrofon nutzen. Tippe stattdessen auf den Bildschirm.',
    'demo.micDenied': 'Kein Zugriff aufs Mikrofon. Tippe auf den Bildschirm oder drück die <b>Leertaste</b>.',
    'demo.micOn': 'Mikrofon an. Drück <b>START</b> und klatsch nach dem Beep. Das Audio bleibt in deinem Browser.',
    'demo.micOnRunning': 'Klatsch für jeden Schuss.',
    'demo.micListening': 'Hört auf Klatschen',
    'demo.micOff': 'Per Klatschen auslösen',
    'demo.shotOne': '1 Schuss', 'demo.shotMany': '{count} Schüsse',
  },
};

/** The string for `key` in the page language, with {placeholders} filled in. */
export function t(key, vars = {}) {
  const s = STRINGS[LANG][key] ?? STRINGS.en[key] ?? key;
  return s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? String(vars[k]) : m));
}

/** "Oct 1, 2026 9:41 AM" / "1. Okt. 2026 09:41", like the app's history and review. */
export function dateTime(d) {
  const date = d.toLocaleDateString(LOCALE, { month: 'short', day: 'numeric', year: 'numeric' });
  return `${date} ${clockTime(d)}`;
}
export const clockTime = (d) => d.toLocaleTimeString(LOCALE, { hour: LANG === 'de' ? '2-digit' : 'numeric', minute: '2-digit' });
export const number = (n) => Math.round(n).toLocaleString(LOCALE);
