// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import { PAGES, pageFor, alternates, nav, footer, sprite, sitemap } from './build/site.js';
import { parseChangelog, renderChangelog, renderChangelogText } from './build/changelog.js';

const root = import.meta.dirname;
// The app's CHANGELOG.md (release-please). A release updates it, which also
// redeploys the site, so the changelog page and the footer version stay current.
const changelogPath = resolve(root, '../CHANGELOG.md');
const releases = () => {
  const all = parseChangelog(readFileSync(changelogPath, 'utf8'));
  // A changelog the parser can't read must fail the build, not deploy a site
  // with an empty changelog page and no version in the footer.
  if (!all.length || !all[0].version) throw new Error(`No release found in ${changelogPath}`);
  return all;
};

/** Throws if any <!--site:...--> placeholder is left in `text`. */
const assertFilled = (text, where) => {
  const left = text.match(/<!--site:[^>]*-->/);
  if (left) throw new Error(`Unfilled placeholder ${left[0]} in ${where}`);
  return text;
};

/** Fills the <!--site:...--> placeholders in every page. */
function siteChrome() {
  return {
    name: 'site-chrome',
    transformIndexHtml: {
      order: 'pre',
      handler(html, ctx) {
        const path = ctx.path.replace(/index\.html$/, '');
        const page = pageFor(path);
        const all = releases();
        const { version } = all[0];
        let out = html
          .replaceAll('<!--site:sprite-->', sprite(root))
          .replaceAll('<!--site:version-->', version);
        if (page) {
          out = out
            .replaceAll('<!--site:alternates-->', alternates(page))
            .replaceAll('<!--site:nav intro-->', nav(page, { intro: true }))
            .replaceAll('<!--site:nav-->', nav(page))
            .replaceAll('<!--site:footer-->', footer(page, version))
            .replaceAll('<!--site:changelog-->', renderChangelog(all, page.lang));
        }
        return assertFilled(out, ctx.path);
      },
    },
    // Files that depend on the changelog are generated too, so a release
    // updates them without anyone touching the site.
    generateBundle() {
      const all = releases();
      this.emitFile({
        type: 'asset',
        fileName: 'sitemap.xml',
        source: sitemap({ '/changelog/': all[0].date }),
      });
      this.emitFile({
        type: 'asset',
        fileName: 'llms-full.txt',
        source: assertFilled(
          readFileSync(resolve(root, 'build/llms-full.txt'), 'utf8')
            .replace('<!--site:changelog-md-->', renderChangelogText(all)),
          'llms-full.txt',
        ),
      });
    },
    configureServer(server) {
      server.watcher.add(changelogPath);
      server.watcher.on('change', (file) => {
        if (resolve(file) === changelogPath) server.ws.send({ type: 'full-reload' });
      });
    },
  };
}

const input = Object.fromEntries([
  ...PAGES.flatMap((p) => [p.en, p.de]).map((url) => [url.replace(/^\/|\/$/g, '').replaceAll('/', '-') || 'index', resolve(root, `.${url}index.html`)]),
  ['404', resolve(root, '404.html')],
  ['de-404', resolve(root, 'de/404.html')],
]);

export default defineConfig({
  plugins: [siteChrome()],
  build: {
    outDir: 'dist',
    rollupOptions: { input },
  },
});
