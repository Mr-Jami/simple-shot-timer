// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
// Page motion, built on Anime.js. House style from Apple's fluid-interface
// guidance: critically damped springs (bounce 0) for everything that moves,
// transform + opacity only, motion that hints at the direction of travel, and
// cross-fades instead of movement when the system asks for reduced motion.
import {
  animate, createTimeline, createTimer, createScope, createDrawable,
  onScroll, spring, stagger, utils,
} from 'animejs';
import { screen, phoneScreen, SAMPLE_SHOTS, sec } from './screens.js';
import { drawHalftone } from './halftone.js';
import { number, t } from './i18n.js';

const settle = spring({ bounce: 0, duration: 700 });
const quick = spring({ bounce: 0, duration: 450 });
const reduceQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
export const reduceMotion = () => reduceQuery.matches;

/** Fires once when `target` scrolls a little way into the viewport. */
const whenSeen = (target, fn, enter = 'bottom-=12% top') =>
  onScroll({ target, enter, repeat: false, onEnter: fn });

/**
 * True when part of `el` is in the viewport right now. This script can run
 * after the first paint, so anything already on screen has been drawn: hiding
 * it to reveal it again would flash. Such elements just stay as they are.
 */
const onScreen = (el) => {
  const r = el.getBoundingClientRect();
  return r.bottom > 0 && r.top < window.innerHeight;
};

// ----- Hero intro: nav, pill, headline words, copy, then the phone -----
export function intro() {
  const root = document.documentElement;
  const h1 = document.querySelector('[data-intro-words]');
  h1.innerHTML = h1.textContent.trim().split(/\s+/)
    .map((w) => `<span class="word-clip"><span>${w}</span></span>`).join(' ');
  const words = h1.querySelectorAll('.word-clip > span');
  const items = document.querySelectorAll('[data-intro]');
  const phone = document.querySelector('[data-intro-phone]');

  // On a slow connection the CSS fallback (site.css, `intro-fallback`) may have
  // shown the hero before this script arrived. motion-ready removes that
  // animation and its fill, so pin the hero visible and skip the replay.
  if (Number(getComputedStyle(h1).opacity) > 0) {
    utils.set([...items, phone, h1], { opacity: 1 });
    root.classList.add('motion-ready');
    return;
  }

  root.classList.add('motion-ready');
  utils.set(h1, { opacity: 1 });

  if (reduceMotion()) {
    animate([...items, phone, ...words], { opacity: [0, 1], duration: 400, ease: 'out(2)' });
    return;
  }
  utils.set(words, { y: '105%' });
  createTimeline({ defaults: { ease: settle } })
    .add('.nav', { opacity: [0, 1], y: [-14, 0] }, 0)
    .add('.hero .hero-pill', { opacity: [0, 1], y: [14, 0] }, 120)
    .add(words, { y: ['105%', '0%'] }, stagger(90, { start: 200 }))
    .add('.hero .lede', { opacity: [0, 1], y: [18, 0] }, 460)
    .add('.hero .cta-row', { opacity: [0, 1], y: [18, 0] }, 540)
    .add('.hero .trust', { opacity: [0, 1], y: [18, 0] }, 620)
    .add(phone, { opacity: [0, 1], y: [72, 0], ease: spring({ bounce: 0, duration: 1100 }) }, 260);
}

// ----- Generic reveals: fade + rise once, children of a group in sequence -----
function reveals() {
  const rise = reduceMotion() ? 0 : 28;
  document.querySelectorAll('[data-reveal]').forEach((el) => {
    if (onScreen(el)) return;
    utils.set(el, { opacity: 0, y: rise });
    whenSeen(el, () => animate(el, { opacity: 1, y: 0, ease: settle }));
  });
  document.querySelectorAll('[data-reveal-group]').forEach((group) => {
    if (onScreen(group)) return;
    const kids = [...group.children];
    utils.set(kids, { opacity: 0, y: rise });
    whenSeen(group, () => animate(kids, { opacity: 1, y: 0, ease: settle, delay: stagger(70) }));
  });
}

// ----- Spec numbers count to their value (the price counts down from $100) -----
function counters() {
  document.querySelectorAll('[data-count]').forEach((el) => {
    const to = Number(el.dataset.count);
    const from = Number(el.dataset.from ?? 0);
    const fmt = number;
    if (reduceMotion() || onScreen(el)) return;
    const n = { v: from };
    el.textContent = fmt(from);
    whenSeen(el, () => animate(n, {
      v: to, duration: 1600, ease: 'out(4)',
      onUpdate: () => { el.textContent = fmt(n.v); },
    }), 'bottom-=8% top');
  });
}

// ----- Story: sticky phone on wide screens, one phone per step otherwise -----
function story() {
  const steps = [...document.querySelectorAll('.story-steps .step')];
  const stage = document.getElementById('story-phone');
  const names = steps.map((s) => s.dataset.screen);

  // Small screens: each step carries its own static phone.
  steps.forEach((s) => { s.querySelector('.phone-step').innerHTML = phoneScreen(screen(s.dataset.screen)); });
  // Wide screens: one phone, a layer per step.
  stage.innerHTML = phoneScreen(names.map((n) => `<div class="layer" data-layer="${n}">${screen(n)}</div>`).join(''));
  const layers = [...stage.querySelectorAll('.layer')];
  const runLayer = stage.querySelector('[data-layer="running"]');

  createScope({ mediaQueries: { wide: '(min-width: 1000px)' } }).add((self) => {
    const texts = steps.map((s) => s.querySelector('.step-text'));
    if (!self.matches.wide) {
      const rise = reduceMotion() ? 0 : 28;
      steps.forEach((s) => {
        if (onScreen(s)) return;
        const parts = [s.querySelector('.step-text'), s.querySelector('.phone-step')];
        utils.set(parts, { opacity: 0, y: rise });
        whenSeen(s, () => animate(parts, { opacity: 1, y: 0, ease: settle, delay: stagger(90) }));
      });
      return;
    }

    let active = -1;
    // The dimmed step text is a CSS starting state (site.css), so it is right
    // from the first paint; activate() animates from there.
    utils.set(layers, { opacity: 0 });
    const live = runningLoop(runLayer);

    const activate = (i) => {
      if (i === active) return;
      // New screen comes from the direction you're scrolling, old one leaves the other way.
      const dir = i > active ? 1 : -1;
      const shift = reduceMotion() || active < 0 ? 0 : 36;
      if (active >= 0) {
        animate(layers[active], { opacity: 0, y: -dir * shift, ease: quick });
        animate(texts[active], { opacity: 0.28, ease: quick });
      }
      animate(layers[i], { opacity: [0, 1], y: [dir * shift, 0], ease: quick });
      animate(texts[i], { opacity: 1, ease: quick });
      if (names[i] === 'running') live.restart(); else live.pause();
      active = i;
    };
    steps.forEach((s, i) => onScroll({
      target: s,
      enter: 'center top',
      leave: 'center bottom',
      onEnter: () => activate(i),
    }));
    activate(0);
    return () => live.pause();
  });
}

/** The running screen replays a five-shot string while its step is active. */
function runningLoop(layer) {
  const q = (r) => layer.querySelector(`[data-ref="${r}"]`);
  const label = q('label'); const num = q('num'); const count = q('shots');
  const first = q('first'); const split = q('split'); const level = q('level');
  const LOOP = 4600;
  const START = 500; // a beat on 0.00 before the clock runs
  let fired = 0;
  const render = (now) => {
    const ms = Math.max(0, now - START);
    const done = SAMPLE_SHOTS.filter((s) => s <= ms);
    if (done.length !== fired) {
      fired = done.length;
      if (fired && !reduceMotion()) animate(num, { scale: [1, 1.06, 1], duration: 120, ease: 'out(2)' });
      if (fired) animate(level, { width: ['94%', '6%'], duration: 480, ease: 'out(3)' });
    }
    const n = done.length;
    label.textContent = n ? t('home.last') : t('home.time');
    num.textContent = sec(n ? done[n - 1] : ms);
    count.textContent = String(n);
    first.textContent = n ? sec(done[0]) : '--';
    split.textContent = n > 1 ? `${sec(done[n - 1] - done[n - 2])}s` : '--';
  };
  if (reduceMotion()) {
    render(START + 1910);
    return { restart() {}, pause() {} };
  }
  const timer = createTimer({
    duration: LOOP, loop: true, autoplay: false,
    onUpdate: (self) => render(self.iterationCurrentTime),
    onLoop: () => { fired = 0; },
  });
  return { restart: () => timer.restart().play(), pause: () => timer.pause() };
}

// ----- Bento visuals: each loop only runs while its card is on screen -----
const whileVisible = (card, timer) => onScroll({
  target: card,
  enter: 'bottom top',
  leave: 'top bottom',
  onEnter: () => timer.play(),
  onLeave: () => timer.pause(),
});

function bento() {
  const card = (name) => document.querySelector(`[data-viz="${name}"]`);
  const still = reduceMotion();

  // Auto-configure: a scrolling level history; loud peaks cross the red line
  // and count as captures, then the suggestion lights up.
  {
    const c = card('autoconfig');
    const barsEl = c.querySelector('.ac-bars');
    const N = 34;
    barsEl.innerHTML = '<i></i>'.repeat(N);
    const bars = [...barsEl.children];
    const nEl = c.querySelector('.ac-n');
    const out = c.querySelector('.ac-suggest');
    const THR = 0.64;
    const SCRIPT = [5, 13, 20, 28]; // which steps are shots
    const CYCLE = 48;
    let levels = Array.from({ length: N }, () => 0.06 + Math.random() * 0.1);
    let step = 0;
    let caught = 0;
    const paint = () => bars.forEach((b, i) => {
      b.style.height = `${levels[i] * 100}%`;
      b.classList.toggle('hot', levels[i] > THR);
    });
    // Starts dimmed in CSS (site.css), so it never paints bright first.
    if (still) {
      levels = levels.map((v, i) => ([6, 14, 22, 29].includes(i) ? 0.92 : v));
      paint();
      nEl.textContent = '4';
      utils.set(out, { opacity: 1 });
    } else {
      paint();
      const loop = createTimer({
        duration: 150, loop: true, autoplay: false,
        onLoop: () => {
          step = (step + 1) % CYCLE;
          if (step === 0) {
            caught = 0;
            nEl.textContent = '0';
            animate(out, { opacity: 0.35, y: 0, ease: quick });
          }
          const shot = SCRIPT.includes(step);
          levels = [...levels.slice(1), shot ? 0.86 + Math.random() * 0.12 : 0.05 + Math.random() * 0.13];
          paint();
          if (shot) {
            caught += 1;
            nEl.textContent = String(caught);
            animate(nEl, { scale: [1, 1.25, 1], duration: 220, ease: 'out(2)' });
            if (caught === SCRIPT.length) animate(out, { opacity: [0.35, 1], y: [8, 0], ease: settle });
          }
        },
      });
      whileVisible(c, loop);
    }
  }

  // Flash and buzz: the screen lights with the beep, the wave pulses.
  {
    const c = card('flash');
    const glow = c.querySelector('.fl-glow');
    const label = c.querySelector('.fl-label');
    const wave = c.querySelectorAll('.fl-wave span');
    const phone = c.querySelector('.fl-phone');
    if (still) {
      utils.set(glow, { opacity: 0 });
      phone.style.boxShadow = 'inset 0 0 0 3px #222, inset 0 0 0 9px #fff';
    } else {
      const tl = createTimeline({ loop: true, loopDelay: 1400, autoplay: false })
        .add(wave, { scaleY: [1, 1.6, 1], backgroundColor: ['#333', '#fee036', '#333'], duration: 420, ease: 'out(2)' }, stagger(40))
        .add(glow, { opacity: [0.95, 0], duration: 420, ease: 'out(3)' }, 0)
        .add(label, { color: ['#000', '#555'], duration: 420, ease: 'out(3)' }, 0)
        .add(phone, { x: [0, -2, 2, -1, 0], duration: 260, ease: 'linear' }, 0);
      whileVisible(c, tl);
    }
  }

  // Background: the foreground-service notification keeps time.
  {
    const c = card('background');
    const time = c.querySelector('.bg-time');
    let s = 12;
    const loop = createTimer({
      duration: 1000, loop: true, autoplay: false,
      onLoop: () => { s += 1; time.textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; },
    });
    whileVisible(c, loop);
  }

  // Latency: the heard beep trails the sent one, and the gap is measured.
  {
    const c = card('latency');
    const b = c.querySelector('.lt-b');
    const brace = c.querySelector('.lt-brace');
    const ms = c.querySelector('.lt-ms');
    const parts = [b, brace, ms];
    if (still) {
      b.style.left = '48%'; brace.style.width = '30%'; ms.style.opacity = '1';
    } else {
      // A fresh one-shot timeline per cycle, so every cycle starts clean.
      const cycle = () => {
        utils.set(parts, { opacity: 1 });
        utils.set(b, { left: '18%' });
        utils.set(brace, { width: '0%' });
        utils.set(ms, { opacity: 0, y: 6 });
        createTimeline({ defaults: { ease: settle } })
          .add(b, { left: '48%' }, 250)
          .add(brace, { width: '30%' }, 250)
          .add(ms, { opacity: 1, y: 0 }, 600)
          .add(parts, { opacity: 0, duration: 320, ease: 'out(2)' }, 3000);
      };
      const loop = createTimer({ duration: 3800, loop: true, autoplay: false, onBegin: cycle, onLoop: cycle });
      whileVisible(c, loop);
    }
  }

  // Languages: "Ready" in each of the app's five languages.
  {
    const c = card('languages');
    const word = c.querySelector('.lg-word');
    const code = c.querySelector('.lg-code');
    const LANGS = [['Ready', 'EN'], ['Bereit', 'DE'], ['Listo', 'ES'], ['Prêt', 'FR'], ['Готов', 'RU']];
    let i = 0;
    const loop = createTimer({
      duration: 1700, loop: true, autoplay: false,
      onLoop: () => {
        i = (i + 1) % LANGS.length;
        const old = word.firstElementChild;
        const next = document.createElement('span');
        next.textContent = LANGS[i][0];
        code.textContent = LANGS[i][1];
        word.appendChild(next);
        if (still) { old.remove(); return; }
        utils.set(word, { position: 'relative' });
        utils.set(next, { position: 'absolute', left: 0, right: 0, top: 0 });
        animate(old, { y: ['0%', '-100%'], opacity: [1, 0], ease: quick, onComplete: () => old.remove() });
        animate(next, { y: ['100%', '0%'], opacity: [0, 1], ease: quick, onComplete: () => utils.set(next, { position: 'static' }) });
      },
    });
    whileVisible(c, loop);
  }

  // Themes and the muted notice arrive once.
  if (!still) {
    const th = card('themes').querySelectorAll('.tm');
    if (!onScreen(card('themes'))) utils.set(th, { y: 60 });
    whenSeen(card('themes'), () => animate(th, { y: 0, ease: settle, delay: stagger(90, { start: 150 }) }));
    const note = card('muted').querySelector('.mt-notice');
    if (!onScreen(card('muted'))) utils.set(note, { y: 40, opacity: 0 });
    whenSeen(card('muted'), () => animate(note, { y: 0, opacity: 1, ease: settle, delay: 200 }));
  }
}

// ----- FAQ: <details> that open and close on an interruptible spring -----
function faq() {
  document.querySelectorAll('.faq details').forEach((d) => {
    const summary = d.querySelector('summary');
    const panel = d.querySelector('.faq-a');
    const ico = d.querySelector('.faq-ico');
    let closing = false;
    summary.addEventListener('click', (e) => {
      if (reduceMotion()) return; // native toggle, no motion
      e.preventDefault();
      const opening = !d.open || closing;
      if (opening) {
        closing = false;
        const from = d.open ? panel.offsetHeight : 0;
        d.open = true;
        const to = panel.scrollHeight;
        animate(panel, { height: [from, to], ease: quick, onComplete: () => { panel.style.height = ''; } });
        animate(ico, { rotate: 45, ease: quick });
      } else {
        closing = true;
        animate(panel, { height: [panel.offsetHeight, 0], ease: quick, onComplete: () => { d.open = false; closing = false; panel.style.height = ''; } });
        animate(ico, { rotate: 0, ease: quick });
      }
    });
    d.addEventListener('toggle', () => { if (reduceMotion()) ico.style.transform = d.open ? 'rotate(45deg)' : ''; });
  });
}

// ----- Download: the mark draws itself, the halftone rises with scroll -----
function download() {
  const section = document.getElementById('download');
  const canvas = section.querySelector('.cta-halftone');
  const state = { p: reduceMotion() ? 1 : 0 };
  const draw = () => drawHalftone(canvas, state.p);
  new ResizeObserver(draw).observe(canvas);
  if (!reduceMotion()) {
    animate(state, {
      p: 1, ease: 'linear',
      autoplay: onScroll({ target: section, enter: 'bottom top', leave: 'bottom bottom', sync: 0.25 }),
      onUpdate: draw,
    });
    const mark = section.querySelector('.cta-mark');
    if (!onScreen(mark)) {
      const strokes = createDrawable(mark.querySelectorAll('path'));
      utils.set(strokes, { draw: '0 0' });
      whenSeen(mark, () => animate(strokes, {
        draw: ['0 0', '0 1'], duration: 900, ease: 'inOut(3)', delay: stagger(140),
      }), 'bottom-=10% top');
    }
  }
}

export function initMotion() {
  reveals();
  counters();
  story();
  bento();
  faq();
  download();
}
