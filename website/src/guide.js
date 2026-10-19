// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
// Guide pages: marks the section being read in "On this page". The links
// work without it; this only adds aria-current, which the CSS highlights.
const links = [...document.querySelectorAll('.guide-toc a[href^="#"]')];
const sections = links.map((a) => document.getElementById(decodeURIComponent(a.hash.slice(1))));

if (links.length && sections.every(Boolean)) {
  let current = -1;
  const update = () => {
    // The section whose heading has passed a line a third of the way down.
    const line = innerHeight / 3;
    let index = -1;
    sections.forEach((s, i) => { if (s.getBoundingClientRect().top <= line) index = i; });
    // At the bottom of the page the last section is the one on screen.
    if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) index = sections.length - 1;
    if (index === current) return;
    current = index;
    links.forEach((a, i) => {
      if (i === index) a.setAttribute('aria-current', 'location');
      else a.removeAttribute('aria-current');
    });
  };
  let queued = false;
  addEventListener('scroll', () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; update(); });
  }, { passive: true });
  addEventListener('resize', update);
  update();
}
