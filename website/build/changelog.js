// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

// Turns the repository's CHANGELOG.md (written by release-please) into the
// /changelog/ pages at build time. Entries are rewritten for app users with the
// same rules as .github/scripts/play_release_notes.py, so the site says what
// the Play Store "What's new" says: no scopes, links or commit hashes, and only
// the sections users notice.

// release-please section heading -> our section key, in output order.
const SECTIONS = {
  'breaking changes': 'changed',
  features: 'new',
  'bug fixes': 'fixes',
  performance: 'improvements',
};
const ORDER = ['changed', 'new', 'fixes', 'improvements'];

const LABELS = {
  en: {
    changed: 'Changed', new: 'New', fixes: 'Fixes', improvements: 'Improvements',
    fallback: 'Bug fixes and improvements.',
    latest: 'Latest', details: 'Details on GitHub', version: 'Version',
    locale: 'en-GB',
  },
  de: {
    changed: 'Geändert', new: 'Neu', fixes: 'Fehlerbehebungen', improvements: 'Verbesserungen',
    fallback: 'Fehlerbehebungen und Verbesserungen.',
    latest: 'Aktuell', details: 'Details auf GitHub', version: 'Version',
    locale: 'de-DE',
  },
};

/** Same rewrite as play_release_notes.py clean_entry(). */
export function cleanEntry(text) {
  let s = text;
  s = s.replace(/,\s*closes\s+\[?#.*$/i, ''); // ", closes [#24](...)"
  s = s.replace(/(\s*\(\[[^\]]*\]\([^)]*\)\))+$/, ''); // trailing ([#25](url)) ([83fcee8](url))
  s = s.replace(/^\*\*[^*]+:\*\*\s*/, ''); // leading **scope:**
  s = s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1'); // other links -> label
  s = s.replace(/\*\*(.+?)\*\*/g, '$1');
  s = s.replace(/`(.+?)`/g, '$1');
  s = s.replace(/\s+/g, ' ').trim().replace(/\.+$/, '');
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** [{ version, url, date, sections: [[key, entries[]], ...] }], newest first. */
export function parseChangelog(md) {
  const releases = [];
  let rel = null;
  let sec = null;
  for (const line of md.split(/\r?\n/)) {
    // "## [2.1.0](https://…/compare/v2.0.0...v2.1.0) (2026-10-04)" or "## 1.0.0 (2026-05-14)"
    const h2 = line.match(/^##\s+(?:\[([^\]]+)\]\(([^)]+)\)|(\S+))(?:\s+\((\d{4}-\d{2}-\d{2})\))?/);
    if (h2) {
      const version = h2[1] || h2[3];
      // Only released versions count. A hand-added "## Unreleased" (or any other
      // non-semver heading) and its entries are skipped, so it can never show up
      // as the latest version.
      rel = /^\d+\.\d+\.\d+/.test(version)
        ? { version, url: h2[2] || null, date: h2[4] || null, raw: {} }
        : null;
      if (rel) releases.push(rel);
      sec = null;
      continue;
    }
    const h3 = line.match(/^###\s+(.*)$/);
    if (h3) {
      sec = SECTIONS[h3[1].replace(/^[^\w]+/, '').trim().toLowerCase()] || null;
      if (rel && sec) rel.raw[sec] ??= [];
      continue;
    }
    if (!rel || !sec) continue;
    const bullet = line.match(/^\s*[*-]\s+(.*)$/);
    if (bullet) rel.raw[sec].push(bullet[1]);
    else if (line.trim() && rel.raw[sec].length) rel.raw[sec][rel.raw[sec].length - 1] += ` ${line.trim()}`;
  }
  return releases.map(({ raw, ...r }) => ({
    ...r,
    sections: ORDER
      .map((key) => [key, [...new Set((raw[key] || []).map(cleanEntry).filter(Boolean))]])
      .filter(([, entries]) => entries.length),
  }));
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function formatDate(iso, locale) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString(locale, { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

export function renderChangelog(releases, lang) {
  const t = LABELS[lang];
  const items = releases.map((r, i) => {
    const body = r.sections.length
      ? r.sections.map(([key, entries]) => `
          <h3>${t[key]}</h3>
          <ul${lang === 'en' ? '' : ' lang="en"'}>${entries.map((e) => `<li>${esc(e)}</li>`).join('')}</ul>`).join('')
      : `<p>${t.fallback}</p>`;
    return `
      <li class="release" id="v${esc(r.version)}">
        <div class="release-head">
          <h2 class="release-ver"><span class="sr-only">${t.version} </span>${esc(r.version)}${i === 0 ? ` <span class="release-latest">${t.latest}</span>` : ''}</h2>
          ${r.date ? `<p class="release-date"><time datetime="${r.date}">${formatDate(r.date, t.locale)}</time></p>` : ''}
        </div>
        <div class="release-body">${body}
          ${r.url ? `<p class="release-link"><a href="${esc(r.url)}" rel="noopener">${t.details}</a></p>` : ''}
        </div>
      </li>`;
  }).join('');
  return `<ol class="releases">${items}\n    </ol>`;
}

/** Plain-text version for llms-full.txt. */
export function renderChangelogText(releases) {
  const t = LABELS.en;
  return releases.map((r) => {
    const head = `### ${r.version}${r.date ? ` (${r.date})` : ''}`;
    const body = r.sections.length
      ? r.sections.map(([key, entries]) => `${t[key]}:\n${entries.map((e) => `- ${e}`).join('\n')}`).join('\n\n')
      : t.fallback;
    return `${head}\n\n${body}`;
  }).join('\n\n');
}
