// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
// The hero phone: a playable shot timer. START, a random delay, the app's
// 2325 Hz beep, then a simulated five-shot string with realistic splits.
// The demo never touches the microphone.
import { animate, spring } from 'animejs';
import {
  icon, statusBar, navBar, readyView, standbyView, runningView, reviewPage,
  drillsTab, historyTab, settingsTab, phoneScreen, sec, lastLine, headerLine, historyItem,
} from './screens.js';
import { t, clockTime, dateTime } from './i18n.js';

const BEEP_HZ = 2325; // AudioService.beepFrequencyHz
const BEEP_MS = 300; // AudioService.startBeepDurationMs
const DELAY_MIN_MS = 1200;
const DELAY_MAX_MS = 3200;
const STOP_AFTER_LAST_MS = 900; // the string ends itself shortly after the last shot

/** A five-shot string: a draw to the first shot, then four splits. Varies per run. */
const simulatedString = () => {
  const between = (lo, hi) => lo + Math.random() * (hi - lo);
  const times = [Math.round(between(1250, 1650))];
  for (let i = 1; i < 5; i++) times.push(times[i - 1] + Math.round(between(195, 290)));
  return times;
};

const firm = spring({ bounce: 0, duration: 350 });

const clockText = () => {
  const d = new Date();
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
};
const shotWord = (n) => (n === 1 ? t('demo.shotOne') : t('demo.shotMany', { count: n }));

export function initDemo({ phone, hint, reduceMotion }) {
  phone.innerHTML = phoneScreen(`
    ${statusBar(clockText())}
    <div class="shell">
      <div class="tab" data-pane="0" data-ref="timerTab">
        <div class="tarea">
          <div class="tv" data-view="ready">${readyView({ last: '', drill: '' })}</div>
          <div class="tv" data-view="standby" hidden style="opacity:0">${standbyView('')}</div>
          <div class="tv" data-view="running" hidden style="opacity:0">${runningView({ label: t('home.time'), num: '0.00', shots: '0', first: '--', split: '--', level: 6 })}</div>
          <div class="tv" data-view="finished" hidden style="opacity:0">
            <div class="fin-centre"><div class="big-label">${t('home.total')}</div><div class="big-num" data-ref="total">0.00</div></div>
            <div class="fin-bottom">
              <div class="stats">
                <div class="stat"><span class="l">${t('home.stat.shots')}</span><span class="v" data-ref="fShots">0</span></div>
                <div class="stat"><span class="l">${t('home.stat.first')}</span><span class="v" data-ref="fFirst">--</span></div>
                <div class="stat"><span class="l">${t('home.stat.split')}</span><span class="v" data-ref="fSplit">--</span></div>
              </div>
              <div class="obtns">
                <button class="obtn" type="button" data-ref="reviewBtn">${icon('list')}${t('home.review')}</button>
                <button class="obtn" type="button" data-ref="addBtn">${icon('add')}${t('home.addShot')}</button>
              </div>
              <div class="saved" data-ref="saved"></div>
            </div>
          </div>
          <div class="tv" data-view="noshots" hidden style="opacity:0">
            <div class="centre-all">
              <svg class="i" style="width:96px;height:96px" aria-hidden="true"><use href="#i-timer"/></svg>
              <div class="noshots-t">${t('home.noShotsDetected')}</div>
              <div class="noshots-s">${t('home.noShotsHint')}</div>
            </div>
          </div>
        </div>
        <button class="bigbtn" type="button" data-ref="go" aria-label="${t('demo.startLabel')}">${icon('play')}<span>${t('home.start')}</span></button>
      </div>
      <div class="tab" data-pane="1" hidden style="opacity:0">${drillsTab(-1)}</div>
      <div class="tab" data-pane="2" hidden style="opacity:0" data-ref="historyPane">${historyTab()}</div>
      <div class="tab" data-pane="3" hidden style="opacity:0">${settingsTab()}</div>
      ${navBar(0, { buttons: true })}
      <div class="snack" data-ref="snack" hidden></div>
    </div>
    <div data-ref="reviewHost"></div>
    <div class="flash" data-ref="flash"></div>
    <div class="ring" data-ref="ring"></div>
  `);

  const app = phone.querySelector('.app');
  const refs = {};
  app.querySelectorAll('[data-ref]').forEach((el) => { refs[el.dataset.ref] = el; });
  const views = {};
  app.querySelectorAll('[data-view]').forEach((el) => { views[el.dataset.view] = el; });
  const panes = [...app.querySelectorAll('[data-pane]')];
  const navbar = app.querySelector('.navbar');
  const dests = [...navbar.querySelectorAll('[data-dest]')];
  const run = {
    label: views.running.querySelector('[data-ref="label"]'),
    num: views.running.querySelector('[data-ref="num"]'),
    shots: views.running.querySelector('[data-ref="shots"]'),
    first: views.running.querySelector('[data-ref="first"]'),
    split: views.running.querySelector('[data-ref="split"]'),
    level: views.running.querySelector('[data-ref="level"]'),
  };

  let state = 'idle'; // idle | standby | running | finished
  let view = views.ready;
  let tab = 0;
  let shots = [];
  let t0 = 0;
  let delayMs = 0;
  let raf = 0;
  let lastRun = null;
  const runs = [];
  const timers = { shots: [] };

  // ----- hint under the phone -----
  let hintText = '';
  const setHint = (html) => {
    if (html === hintText) return;
    hintText = html;
    hint.innerHTML = html;
  };

  // ----- audio: the app's sine beep, plus a soft tick for each simulated shot -----
  let ctx = null;
  let noise = null;
  const ensureAudio = () => {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    if (!ctx) ctx = new AC({ latencyHint: 'interactive' });
    if (ctx.state === 'suspended') ctx.resume();
  };
  const tone = (at, hz, dur, vol) => {
    // Raised-cosine attack and release, like AudioService._generateWav, so
    // the beep starts without a click.
    const n = 64;
    const up = new Float32Array(n);
    for (let i = 0; i < n; i++) up[i] = vol * (0.5 - 0.5 * Math.cos((Math.PI * i) / (n - 1)));
    const down = up.slice().reverse();
    const ramp = 0.01;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = hz;
    gain.gain.setValueAtTime(0, at);
    gain.gain.setValueCurveAtTime(up, at, ramp);
    gain.gain.setValueCurveAtTime(down, at + dur - ramp, ramp);
    osc.connect(gain).connect(ctx.destination);
    osc.start(at);
    osc.stop(at + dur + 0.02);
  };
  const tick = () => {
    if (!ctx) return;
    if (!noise) {
      const len = Math.floor(ctx.sampleRate * 0.035);
      noise = ctx.createBuffer(1, len, ctx.sampleRate);
      const d = noise.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len) ** 5;
    }
    const src = ctx.createBufferSource();
    const hp = ctx.createBiquadFilter();
    const gain = ctx.createGain();
    src.buffer = noise;
    hp.type = 'highpass';
    hp.frequency.value = 900;
    gain.gain.value = 0.35;
    src.connect(hp).connect(gain).connect(ctx.destination);
    src.start();
  };

  // ----- view + button + nav helpers -----
  const fade = (from, to) => {
    if (from === to) return;
    to.hidden = false;
    animate(to, { opacity: 1, duration: 200, ease: 'out(2)' });
    animate(from, {
      opacity: 0, duration: 140, ease: 'out(2)',
      onComplete: () => { if (from.style.opacity === '0') from.hidden = true; },
    });
  };
  const show = (name) => {
    const next = views[name];
    fade(view, next);
    view = next;
  };
  const setButton = (stop) => {
    refs.go.innerHTML = stop ? `${icon('stop')}<span>${t('home.stop')}</span>` : `${icon('play')}<span>${t('home.start')}</span>`;
    refs.go.setAttribute('aria-label', stop ? t('demo.stopLabel') : t('demo.startLabel'));
    animate(refs.go, {
      backgroundColor: stop ? '#f44336' : '#ffffff',
      color: stop ? '#ffffff' : '#000000',
      duration: 160, ease: 'out(2)',
    });
  };
  const setNavBusy = (busy) => {
    navbar.classList.toggle('dim', busy);
    dests.forEach((d) => { d.disabled = busy; });
  };
  const selectTab = (i) => {
    if (i === tab) return;
    closeReview(true);
    if (tab === 0 && state === 'finished') {
      // Leaving the Timer tab collapses a finished result, as in the app.
      state = 'idle';
      view.hidden = true;
      view.style.opacity = '0';
      view = views.ready;
      view.hidden = false;
      view.style.opacity = '1';
    }
    dests.forEach((d, j) => {
      d.classList.toggle('on', j === i);
      if (j === i) d.setAttribute('aria-current', 'page');
      else d.removeAttribute('aria-current');
    });
    const pill = dests[i].querySelector('.pill');
    if (!reduceMotion()) animate(pill, { scaleX: [0.4, 1], ease: firm });
    fade(panes[tab], panes[i]);
    tab = i;
  };

  const flash = () => {
    if (reduceMotion()) animate(refs.ring, { opacity: [1, 0], duration: 450, ease: 'out(2)' });
    else animate(refs.flash, { opacity: [0.92, 0], duration: 280, ease: 'out(3)' });
    if (navigator.vibrate) navigator.vibrate(40);
  };
  const snack = (text) => {
    clearTimeout(timers.snack);
    refs.snack.textContent = text;
    refs.snack.hidden = false;
    animate(refs.snack, { opacity: [0, 1], y: [16, 0], ease: firm });
    timers.snack = setTimeout(() => {
      animate(refs.snack, { opacity: 0, y: 16, ease: firm, onComplete: () => { refs.snack.hidden = true; } });
    }, 2600);
  };

  // ----- the run -----
  const clearTimers = () => {
    clearTimeout(timers.delay);
    clearTimeout(timers.beep);
    clearTimeout(timers.end);
    timers.shots.forEach(clearTimeout);
    timers.shots = [];
    cancelAnimationFrame(raf);
  };

  function start() {
    closeReview(true);
    ensureAudio();
    clearTimers();
    shots = [];
    state = 'standby';
    run.label.textContent = t('home.time');
    run.num.textContent = '0.00';
    run.shots.textContent = '0';
    run.first.textContent = '--';
    run.split.textContent = '--';
    setButton(true);
    setNavBusy(true);
    show('standby');
    setHint(t('demo.standby'));
    delayMs = DELAY_MIN_MS + Math.random() * (DELAY_MAX_MS - DELAY_MIN_MS);
    timers.delay = setTimeout(beep, delayMs);
  }

  function beep() {
    // Like the app, t=0 is when the beep is heard, not when it is requested:
    // schedule it slightly ahead and add the output latency the browser reports.
    const lead = 0.04;
    let latency = 0;
    if (ctx) {
      tone(ctx.currentTime + lead, BEEP_HZ, BEEP_MS / 1000, 0.16);
      latency = (ctx.outputLatency || 0) + (ctx.baseLatency || 0);
    }
    t0 = performance.now() + (lead + latency) * 1000;
    timers.beep = setTimeout(heard, Math.max(0, t0 - performance.now()));
  }

  function heard() {
    state = 'running';
    // Flash, haptic and the view change land on the same frame as the sound.
    flash();
    show('running');
    setHint(t('demo.go'));
    // Each shot lands at its time after the audible beep (t0).
    const times = simulatedString();
    timers.shots = times.map((ms) => setTimeout(() => shot(ms), Math.max(0, t0 + ms - performance.now())));
    timers.end = setTimeout(stop, Math.max(0, t0 + times[times.length - 1] + STOP_AFTER_LAST_MS - performance.now()));
    const loop = () => {
      if (state !== 'running') return;
      if (!shots.length) run.num.textContent = sec(Math.max(0, performance.now() - t0));
      raf = requestAnimationFrame(loop);
    };
    loop();
  }

  function shot(ms) {
    if (state !== 'running') return;
    shots.push(ms);
    const n = shots.length;
    run.label.textContent = t('home.last');
    run.num.textContent = sec(ms);
    run.shots.textContent = String(n);
    run.first.textContent = sec(shots[0]);
    run.split.textContent = n > 1 ? `${sec(shots[n - 1] - shots[n - 2])}s` : '--';
    // The app's 120 ms scale tick on every detected shot.
    if (!reduceMotion()) animate(run.num, { scale: [1, 1.06, 1], duration: 120, ease: 'out(2)' });
    animate(run.level, { width: ['94%', '6%'], duration: 480, ease: 'out(3)' });
    tick();
  }

  function stop() {
    if (state === 'standby') {
      clearTimers();
      state = 'idle';
      setButton(false);
      setNavBusy(false);
      show('ready');
      setHint(t('demo.cancelled'));
      return;
    }
    if (state !== 'running') return;
    clearTimers();
    state = 'finished';
    setButton(false);
    setNavBusy(false);
    const n = shots.length;
    if (!n) {
      show('noshots');
      setHint(t('demo.noShots'));
      return;
    }
    const at = new Date();
    lastRun = { shots: shots.slice(), at, delayMs };
    const total = sec(shots[n - 1]);
    refs.total.textContent = total;
    refs.fShots.textContent = String(n);
    refs.fFirst.textContent = sec(shots[0]);
    refs.fSplit.textContent = n > 1 ? `${sec(shots[n - 1] - shots[n - 2])}s` : '--';
    refs.saved.textContent = t('home.savedAt', { time: clockTime(at) });
    views.ready.innerHTML = readyView({ last: lastLine(shots[n - 1], n), drill: '' });
    runs.unshift(historyItem(shots, at));
    refs.historyPane.innerHTML = historyTab(runs);
    show('finished');
    setHint(t('demo.done', { shots: shotWord(n), total }));
  }

  // ----- review page: slides in from the right, leaves the same way -----
  function openReview() {
    if (!lastRun) return;
    refs.reviewHost.innerHTML = reviewPage({
      time: clockText(),
      date: dateTime(lastRun.at),
      head: headerLine(lastRun.delayMs),
      label: '',
      shots: lastRun.shots,
    }, { back: true, scroll: true });
    const page = refs.reviewHost.firstElementChild;
    if (reduceMotion()) animate(page, { opacity: [0, 1], duration: 200, ease: 'out(2)' });
    else animate(page, { x: ['100%', '0%'], ease: firm });
    page.querySelector('[data-ref="back"]').addEventListener('click', () => closeReview());
    page.querySelector('[data-ref="back"]').focus({ preventScroll: true });
    setHint(t('demo.review'));
  }
  function closeReview(instant = false) {
    const page = refs.reviewHost.firstElementChild;
    if (!page) return;
    if (instant) { page.remove(); return; }
    const done = () => page.remove();
    if (reduceMotion()) animate(page, { opacity: 0, duration: 160, ease: 'out(2)', onComplete: done });
    else animate(page, { x: '100%', ease: firm, onComplete: done });
    refs.reviewBtn.focus({ preventScroll: true });
    if (state === 'finished') setHint(t('demo.again'));
  }

  // ----- input -----
  refs.go.addEventListener('click', () => {
    if (state === 'standby' || state === 'running') stop();
    else start();
  });
  refs.reviewBtn.addEventListener('click', openReview);
  refs.addBtn.addEventListener('click', () => snack(t('demo.addShotSnack')));
  navbar.addEventListener('click', (e) => {
    const d = e.target.closest('[data-dest]');
    if (d && !d.disabled) selectTab(Number(d.dataset.dest));
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      if (state === 'standby' || state === 'running') stop();
    }
  });
  setInterval(() => app.querySelectorAll('.clock').forEach((c) => { c.textContent = clockText(); }), 20000);

}
