// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// Build-time page chrome shared by every page and both languages: navigation
// with the language switch, footer, canonical + hreflang links, and the icon
// sprite. Pages hold <!--site:...--> placeholders that vite.config.js fills in.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const ORIGIN = 'https://simpleshottimer.com';
const PLAY = 'https://play.google.com/store/apps/details?id=cc.jami.simpleshottimer';
const REPO = 'https://github.com/Mr-Jami/simple-shot-timer';

/** Every page in both languages. The English URL is also x-default. */
export const PAGES = [
  { en: '/', de: '/de/' },
  { en: '/changelog/', de: '/de/changelog/' },
  { en: '/privacy/', de: '/de/datenschutz/' },
  { en: '/privacy/website/', de: '/de/datenschutz/website/' },
  { en: '/imprint/', de: '/de/impressum/' },
];

const link = (key, lang) => PAGES.find((p) => p.en === key)[lang];

const T = {
  en: {
    navLabel: 'Main',
    features: 'Features',
    privacy: 'Privacy',
    faq: 'FAQ',
    getApp: 'Get the app',
    switchLabel: 'Deutsch',
    tagline: 'The free and open-source shot timer app. Made in Hamburg by',
    jamiIt: 'https://jami-it.de/en/',
    app: 'App',
    changelog: 'Changelog',
    beta: 'Join the beta',
    project: 'Project',
    source: 'Source code',
    bug: 'Report a bug',
    license: 'License (GPLv3)',
    legal: 'Legal',
    appPrivacy: 'App privacy policy',
    sitePrivacy: 'Website privacy policy',
    imprint: 'Imprint',
    version: 'Version',
    trademark: 'Google Play and the Google Play logo are trademarks of Google LLC.',
    footerLabel: 'Footer',
  },
  de: {
    navLabel: 'Hauptmenü',
    features: 'Funktionen',
    privacy: 'Datenschutz',
    faq: 'FAQ',
    getApp: 'App laden',
    switchLabel: 'English',
    tagline: 'Die kostenlose Open-Source-Shot-Timer-App. Gemacht in Hamburg von',
    jamiIt: 'https://jami-it.de/',
    app: 'App',
    changelog: 'Neuerungen',
    beta: 'Beim Beta-Test mitmachen',
    project: 'Projekt',
    source: 'Quellcode',
    bug: 'Fehler melden',
    license: 'Lizenz (GPLv3)',
    legal: 'Rechtliches',
    appPrivacy: 'Datenschutz der App',
    sitePrivacy: 'Datenschutz der Website',
    imprint: 'Impressum',
    version: 'Version',
    trademark: 'Google Play und das Google Play-Logo sind Marken von Google LLC.',
    footerLabel: 'Fußzeile',
  },
};

// Inline so the chrome needs no sprite (only the homepages carry one).
const MARK = '<svg class="mark" viewBox="103 91 320 320" width="26" height="26" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="26" stroke-linecap="round"><path d="M278 147A105 105 0 1 1 264 355"/><path d="M133 207H237"/><path d="M159 264H208"/></g><circle cx="184" cy="315" r="13" fill="currentColor"/></svg>';

/** The page entry for a URL path, or null for pages outside the registry (404). */
export function pageFor(path) {
  for (const p of PAGES) {
    if (p.en === path) return { lang: 'en', self: p.en, other: p.de, pair: p };
    if (p.de === path) return { lang: 'de', self: p.de, other: p.en, pair: p };
  }
  return null;
}

export function alternates(page) {
  return [
    `<link rel="canonical" href="${ORIGIN}${page.self}">`,
    `<link rel="alternate" hreflang="en" href="${ORIGIN}${page.pair.en}">`,
    `<link rel="alternate" hreflang="de" href="${ORIGIN}${page.pair.de}">`,
    `<link rel="alternate" hreflang="x-default" href="${ORIGIN}${page.pair.en}">`,
  ].join('\n  ');
}

export function nav(page, { intro = false } = {}) {
  const t = T[page.lang];
  const home = link('/', page.lang);
  const other = page.lang === 'en' ? 'de' : 'en';
  return `<header class="nav"${intro ? ' data-intro' : ''}>
  <nav class="nav-bar" aria-label="${t.navLabel}">
    <a class="nav-brand" href="${home}">${MARK}<span>Simple Shot Timer</span></a>
    <ul class="nav-links">
      <li><a href="${home}#features">${t.features}</a></li>
      <li><a href="${home}#privacy">${t.privacy}</a></li>
      <li><a href="${home}#faq">${t.faq}</a></li>
    </ul>
    <a class="nav-lang" href="${page.other}" hreflang="${other}" lang="${other}" title="${t.switchLabel}">${other.toUpperCase()}<span class="sr-only"> (${t.switchLabel})</span></a>
    <a class="btn btn-yellow btn-sm" href="${home}#download">${t.getApp}</a>
  </nav>
</header>`;
}

export function footer(page, version) {
  const t = T[page.lang];
  const l = (key) => link(key, page.lang);
  const cur = (href) => (href === page.self ? ' aria-current="page"' : '');
  const item = (href, label, ext = false) => `<li><a href="${href}"${ext ? ' rel="noopener"' : cur(href)}>${label}</a></li>`;
  const other = page.lang === 'en' ? 'de' : 'en';
  return `<footer class="footer">
  <div class="wrap footer-grid">
    <div class="footer-brand">
      <a class="nav-brand" href="${l('/')}">${MARK}<span>Simple Shot Timer</span></a>
      <p>${t.tagline} <a href="${t.jamiIt}" rel="noopener">Jami IT</a>.</p>
    </div>
    <nav class="footer-cols" aria-label="${t.footerLabel}">
      <div>
        <h2>${t.app}</h2>
        <ul>
          ${item(PLAY, 'Google Play', true)}
          ${item(l('/changelog/'), t.changelog)}
          ${item(`${REPO}/blob/main/JOIN_TESTING.md`, t.beta, true)}
        </ul>
      </div>
      <div>
        <h2>${t.project}</h2>
        <ul>
          ${item(REPO, t.source, true)}
          ${item(`${REPO}/issues`, t.bug, true)}
          ${item(`${REPO}/blob/main/LICENSE`, t.license, true)}
        </ul>
      </div>
      <div>
        <h2>${t.legal}</h2>
        <ul>
          ${item(l('/privacy/'), t.appPrivacy)}
          ${item(l('/privacy/website/'), t.sitePrivacy)}
          ${item(l('/imprint/'), t.imprint)}
        </ul>
      </div>
    </nav>
  </div>
  <div class="wrap footer-base">
    <p>© 2026 Tareq Jami · Jami IT · ${t.version} ${version}</p>
    <p><a class="footer-lang" href="${page.other}" hreflang="${other}" lang="${other}">${t.switchLabel}</a></p>
    <p>${t.trademark}</p>
  </div>
</footer>`;
}

let spriteCache;
export function sprite(root) {
  spriteCache ??= readFileSync(resolve(root, 'build/sprite.html'), 'utf8').trim();
  return spriteCache;
}

/** sitemap.xml: every page with its other-language twin. */
export function sitemap(lastmod = {}) {
  const urls = PAGES.flatMap((p) => [p.en, p.de].map((self) => `  <url>
    <loc>${ORIGIN}${self}</loc>${lastmod[p.en] ? `\n    <lastmod>${lastmod[p.en]}</lastmod>` : ''}
    <xhtml:link rel="alternate" hreflang="en" href="${ORIGIN}${p.en}"/>
    <xhtml:link rel="alternate" hreflang="de" href="${ORIGIN}${p.de}"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="${ORIGIN}${p.en}"/>
  </url>`));
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls.join('\n')}
</urlset>
`;
}
