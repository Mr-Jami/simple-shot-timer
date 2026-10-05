// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
// App screens recreated in HTML. Strings come from assets/i18n via i18n.js,
// layout from branding/store-listing/index.html. Drill names and times are made up.
import { t, LANG, dateTime } from './i18n.js';

export const icon = (id, cls = '') => `<svg class="i ${cls}" width="24" height="24" aria-hidden="true"><use href="#i-${id}"/></svg>`;

export const statusBar = (time = '9:41') =>
  `<div class="status"><span class="clock">${time}</span><span class="dots"><span></span><span></span></span></div>`;

const DESTS = [
  ['timer', 'timer', 'nav.timer'],
  ['bookmarks-o', 'bookmarks-f', 'nav.drills'],
  ['history', 'history', 'nav.history'],
  ['settings-o', 'settings-f', 'nav.settings'],
];

/** Bottom navigation bar. `buttons` makes each destination a real button. */
export function navBar(active = 0, { dim = false, buttons = false } = {}) {
  const tag = buttons ? 'button' : 'div';
  const items = DESTS.map(([o, f, key], i) => {
    const label = t(key);
    const attrs = buttons ? ` type="button" data-dest="${i}" aria-label="${label}"${i === active ? ' aria-current="page"' : ''}` : '';
    return `<${tag} class="dest${i === active ? ' on' : ''}"${attrs}><span class="pill"></span>${icon(o, 'ic-o')}${icon(f, 'ic-f')}<span class="lbl">${label}</span></${tag}>`;
  }).join('');
  return `<div class="navbar${dim ? ' dim' : ''}">${items}</div>`;
}

const modeChip = (mode) => t('home.modeChip', { mode: t(`mode.${mode}`) });

export const summaryChips = (drill = 'El Presidente') => `
  <div class="chips">
    ${drill ? `<span class="chip active">${icon('bookmark')}${drill}</span>` : ''}
    <span class="chip">${modeChip('standard')}</span><span class="chip">${t('home.delayRandom')}</span>
  </div>`;

export const lastLine = (ms, count) =>
  t(count === 1 ? 'home.lastStringOne' : 'home.lastString', { seconds: sec(ms), count });

export const readyView = ({ last = lastLine(2370, 5), drill = 'El Presidente' } = {}) => `
  <div class="centre-all">
    <svg class="i" style="width:96px;height:96px" aria-hidden="true"><use href="#i-timer"/></svg>
    <div class="ready-t">${t('home.ready')}</div>
    <div class="ready-s">${t('home.pressStartToBegin')}</div>
    <div style="margin-top:24px">${summaryChips(drill)}</div>
    ${last ? `<div class="lastline">${last}${icon('chevron')}</div>` : ''}
  </div>`;

export const standbyView = (drill = 'El Presidente') => `
  <div class="topslot">${summaryChips(drill)}</div>
  <div class="centre">
    <svg class="i" style="width:96px;height:96px" aria-hidden="true"><use href="#i-hourglass"/></svg>
    <div class="standby-t">${t('home.standBy')}</div>
  </div>`;

export const runningView = ({ label = t('home.last'), num = '1.91', shots = '3', first = '1.42', split = '0.23s', level = 91 } = {}) => `
  <div class="topslot"></div>
  <div class="centre"><div class="big-label" data-ref="label">${label}</div><div class="big-num" data-ref="num">${num}</div></div>
  <div class="runfoot">
    <div class="stats">
      <div class="stat"><span class="l">${t('home.stat.shots')}</span><span class="v" data-ref="shots">${shots}</span></div>
      <div class="stat"><span class="l">${t('home.stat.first')}</span><span class="v" data-ref="first">${first}</span></div>
      <div class="stat"><span class="l">${t('home.stat.split')}</span><span class="v" data-ref="split">${split}</span></div>
    </div>
    <div class="micline"><div class="fill" data-ref="level" style="width:${level}%"></div><div class="thr"></div></div>
  </div>`;

const bigButton = (stop = false) => stop
  ? `<div class="bigbtn" style="background:#f44336;color:#fff">${icon('stop')}${t('home.stop')}</div>`
  : `<div class="bigbtn">${icon('play')}${t('home.start')}</div>`;

const timerShell = (view, { stop = false, dim = false } = {}) => `
  ${statusBar()}
  <div class="shell">
    <div class="tab"><div class="tarea"><div class="tv">${view}</div></div>${bigButton(stop)}</div>
    ${navBar(0, { dim })}
  </div>`;

export const SAMPLE_SHOTS = [1420, 1680, 1910, 2150, 2370];
// The made-up "now" of the static screens: 1 Oct 2026, 9:41.
const SAMPLE_NOW = new Date(2026, 9, 1, 9, 41);
const minutesAgo = (m) => new Date(SAMPLE_NOW.getTime() - m * 60000);

export function reviewRows(shots) {
  return shots.map((ms, i) => `
    <div class="row"><div class="av">${i + 1}</div><div><div class="rt">${sec(ms)}s</div><div class="rs">${i ? t('review.splitOther', { seconds: sec(ms - shots[i - 1]) }) : t('review.splitFirst')}</div></div></div>`).join('');
}

export function reviewStats(shots) {
  const splits = shots.slice(1).map((ms, i) => ms - shots[i]);
  const avg = splits.length ? splits.reduce((a, b) => a + b, 0) / splits.length : null;
  return {
    total: shots.length ? `${sec(shots[shots.length - 1])}s` : '--',
    first: shots.length ? `${sec(shots[0])}s` : '--',
    fastest: splits.length ? `${sec(Math.min(...splits))}s` : '--',
    slowest: splits.length ? `${sec(Math.max(...splits))}s` : '--',
    average: avg != null ? `${sec(avg)}s` : '--',
    count: String(shots.length),
  };
}

export const headerLine = (delayMs) =>
  t('review.headerLine', { drill: t('mode.standard'), delay: t('delay.random'), seconds: sec(delayMs) });

const SAMPLE_LABEL = { en: 'El Presidente dry run', de: 'El Presidente trocken' }[LANG];

export const reviewBody = ({ date = dateTime(SAMPLE_NOW), head = headerLine(1580), label = SAMPLE_LABEL, shots = SAMPLE_SHOTS } = {}) => {
  const s = reviewStats(shots);
  const cell = (key, v) => `<div class="cell"><span class="l">${t(`review.summary.${key}`)}</span><span class="v">${v}</span></div>`;
  return `
    <div class="rv-date">${date}</div>
    <div class="rv-head">${head}</div>
    <div class="grid">
      ${cell('total', s.total)}${cell('first', s.first)}${cell('fastest', s.fastest)}
      ${cell('slowest', s.slowest)}${cell('average', s.average)}${cell('shots', s.count)}
    </div>
    ${label ? `<div class="field"><span class="fl">${t('review.label')}</span>${label}</div>` : `<div class="field empty">${t('review.label')}</div>`}
    <div class="field notes">${t('review.notes')}</div>
    <div class="pen"><span class="txt">${t('review.penalty', { seconds: '0.00' })}</span><span class="ib">${icon('remove')}</span><span class="ib">${icon('add')}</span></div>
    <div class="hdiv"><span></span></div>
    <div class="shots-h"><span>${t('review.shotsHeader', { count: shots.length })}</span><span class="add-t">${icon('add')}${t('review.add')}</span></div>
    <div class="rows">${reviewRows(shots)}</div>`;
};

export const reviewPage = (opts, { back = false, scroll = false } = {}) => `
  <div class="page">
    <div class="appbar">${statusBar(opts?.time)}
      <div class="bar">${back ? `<button class="icon" type="button" data-ref="back" aria-label="${t('demo.backLabel')}">${icon('back')}</button>` : `<div class="icon">${icon('back')}</div>`}<div class="title">${t('review.title')}</div><div class="icon">${icon('share')}</div></div>
    </div>
    <div class="pbody${scroll ? ' scroll' : ''}"><div class="rv-scroll">${reviewBody(opts)}</div></div>
  </div>`;

const randomDelay = t('home.delayRandom');
const DRILLS = [
  ['El Presidente', `${modeChip('standard')} · ${randomDelay}`],
  ['Bill Drill', `${modeChip('standard')} · ${t('home.delayFixed', { seconds: '2.0' })}`],
  [{ en: 'Draw drill', de: 'Ziehen' }[LANG], `${modeChip('par')} · ${randomDelay} · Par 1.5s × 5`],
  [{ en: 'Stage warm-up', de: 'Stage aufwärmen' }[LANG], `${modeChip('stage')} · ${randomDelay} · Stage 60s`],
  ['Dot torture', `${modeChip('standard')} · ${t('home.delayInstant')}`],
];

export const drillsTab = (on = 1) => `
  <div class="thead"><div class="tt">${t('drills.manageTitle')}</div><div class="act">${icon('bookmark-add')}</div></div>
  <div class="list">${DRILLS.map(([t1, t2], i) => `
    <div class="tile drow${i === on ? ' on' : ''}"><div class="lead">${icon('bookmark-o', 'ic-bm')}${icon('check-circle', 'ic-check')}</div><div class="txt"><div class="t1">${t1}</div><div class="t2">${t2}</div></div><div class="trail">${icon('more')}</div></div>
    <div class="divider"></div>`).join('')}
  </div>`;

const shotsTitle = (ms, count) => t(count === 1 ? 'history.itemFallbackOne' : 'history.itemFallback', { seconds: sec(ms), count });
const HISTORY = [
  [SAMPLE_LABEL, minutesAgo(0), t('mode.standard'), 2370],
  [{ en: 'Bill Drill, cold', de: 'Bill Drill, kalt' }[LANG], minutesAgo(5), t('mode.standard'), 1840],
  [shotsTitle(4120, 6), minutesAgo(15 * 60 + 29), 'Par 2.0s ×5 /5.0s', 4120],
  [{ en: 'Stage 1 walk-through', de: 'Stage 1 Durchgang' }[LANG], minutesAgo(15 * 60 + 43), 'Stage 60.0s', 48200],
  [shotsTitle(2610, 5), minutesAgo(62 * 60 + 36), t('mode.standard'), 2610],
  [{ en: 'Draw drill', de: 'Ziehen' }[LANG], minutesAgo(62 * 60 + 49), 'Par 1.5s ×5 /5.0s', 1380],
  [shotsTitle(2880, 5), minutesAgo(95 * 60 + 27), t('mode.standard'), 2880],
].map(([title, date, config, ms]) => [title, `${dateTime(date)} · ${config}`, `${sec(ms)}s`]);

/** History rows: [title, subtitle, time]. `extra` rows go on top. */
export const historyTab = (extra = []) => `
  <div class="thead"><div class="tt">${t('history.title')}</div><div class="act">${icon('more')}</div></div>
  <div class="list">${[...extra, ...HISTORY].slice(0, 7).map(([t1, t2, n]) => `
    <div class="tile"><div class="txt"><div class="t1" style="font-weight:600">${t1}</div><div class="t2">${t2}</div></div><div class="trail num">${n}</div></div>
    <div class="divider"></div>`).join('')}
  </div>`;

export const historyItem = (shots, at) => {
  const total = shots[shots.length - 1];
  return [shotsTitle(total, shots.length), `${dateTime(at)} · ${t('mode.standard')}`, `${sec(total)}s`];
};

const slider = (label, value, pct) => `
  <div class="sl"><div class="sl-t"><span>${label}</span><span class="sl-v">${value}</span></div><div class="trk"><div class="fill" style="width:${pct}%"></div><div class="th" style="left:${pct}%"></div></div></div>`;

export const settingsTab = () => `
  <div class="thead"><div class="tt">${t('settings.title')}</div></div>
  <div class="variant">
    <div class="sec">${t('settings.section.drillMode')}</div>
    <div class="cchips"><div class="cc on">${icon('check')}${t('mode.standard')}</div><div class="cc">${t('mode.par')}</div><div class="cc">${t('mode.stage')}</div></div>
    <div class="sec">${t('settings.section.startDelay')}</div>
    <div class="cchips"><div class="cc">${t('delay.instant')}</div><div class="cc">${t('delay.fixed')}</div><div class="cc on">${icon('check')}${t('delay.random')}</div></div>
    ${slider(t('settings.randomMin'), '1.0s', 10)}
    ${slider(t('settings.randomMax'), '4.0s', 40)}
    <div class="sec">${t('settings.section.beep')}</div>
    ${slider(t('settings.volume'), '90%', 90)}
    <div class="sw"><span>${t('settings.visualFlash')}</span><div class="swt"><span></span></div></div>
    <div class="sw"><span>${t('settings.hapticOnBeep')}</span><div class="swt"><span></span></div></div>
  </div>`;

/** A full static screen by name, for the story phones. */
export function screen(name) {
  switch (name) {
    case 'ready': return timerShell(readyView());
    case 'standby': return timerShell(standbyView(), { stop: true, dim: true });
    case 'running': return timerShell(runningView(), { stop: true, dim: true });
    case 'review': return reviewPage();
    case 'drills': return `${statusBar()}<div class="shell"><div class="tab">${drillsTab()}</div><div class="snack">${t('drills.appliedSnack', { name: 'Bill Drill' })}</div>${navBar(1)}</div>`;
    case 'history': return `${statusBar()}<div class="shell"><div class="tab">${historyTab()}</div>${navBar(2)}</div>`;
    default: return '';
  }
}

export const phoneScreen = (inner) => `<div class="phone-screen"><div class="app">${inner}</div></div>`;

export function sec(ms) {
  return (ms / 1000).toFixed(2);
}
