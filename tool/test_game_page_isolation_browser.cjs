#!/usr/bin/env node
'use strict';

// Real Chromium check of DMM page isolation around the game frame. All
// documents are local fixtures served by routing; no account data is used.
// Environment: PLAYWRIGHT_MODULE (package name or module directory) and
// CHROME_PATH (installed Edge/Chrome; defaults to the msedge channel).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const dart = fs.readFileSync(
  path.join(__dirname, '../lib/src/browser/game_page_alignment_script.dart'),
  'utf8',
);
const source = /gamePageAlignmentScript\s*=\s*r'''([\s\S]*?)''';/.exec(dart)?.[1];
assert.ok(source, 'Could not extract the production injection');
const playwright = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const gameUrl = 'https://play.games.dmm.com/game/kancolle';
const fixture = `<!doctype html><html><head>
<meta name="viewport" content="width=device-width">
<style>body{margin:8px} header,aside,footer,#notice,#recommend,#portal{height:40px;background:#c33}</style>
</head><body>
<div id="root"><div id="shell">
  <header id="header">header</header>
  <main id="main"><div id="area">
    <div id="notice">notice</div>
    <iframe id="game_frame" src="https://osapi.dmm.com/gadgets/ifr" width="1200" height="720"></iframe>
    <div id="recommend">recommend</div>
  </div></main>
  <aside id="aside">aside</aside>
  <footer id="footer">footer</footer>
  <div id="modal-host"><dialog id="dialog">notice dialog</dialog></div>
  <div id="aria-host"></div>
</div></div>
<div id="portal">portal</div>
<script>window.__fixtureScript = true;</script>
</body></html>`;

const pageChrome = ['header', 'notice', 'recommend', 'aside', 'footer', 'modal-host', 'aria-host', 'portal'];
const gameChain = ['root', 'shell', 'main', 'area', 'game_frame'];

async function main() {
  const browser = await playwright.chromium.launch({
    headless: true,
    ...(process.env.CHROME_PATH ? {executablePath: process.env.CHROME_PATH} : {channel: 'msedge'}),
    args: ['--disable-gpu', '--disable-extensions', '--disable-background-networking', '--no-first-run'],
  });
  let failures = 0;
  try {
    const context = await browser.newContext({viewport: {width: 1200, height: 720}, serviceWorkers: 'block'});
    await context.route('**/*', (route) => route.fulfill({
      status: 200,
      contentType: 'text/html',
      body: route.request().url().startsWith(gameUrl) ? fixture : '<!doctype html><body style="margin:0;background:#123">game</body>',
    }));
    const page = await context.newPage();
    await page.addInitScript(() => {
      window.__messages = [];
      window.YahagiPresentation = {postMessage: (message) => window.__messages.push(message)};
    });
    await page.goto(gameUrl);
    const settle = () => page.evaluate(() => new Promise((resolve) => {
      requestAnimationFrame(() => setTimeout(resolve, 150));
    }));
    const snapshot = () => page.evaluate(({pageChrome, gameChain}) => {
      const read = (id) => {
        const element = document.getElementById(id);
        return {
          isolated: element.hasAttribute('data-yahagi-isolated'),
          display: getComputedStyle(element).display,
        };
      };
      return {
        chrome: Object.fromEntries(pageChrome.map((id) => [id, read(id)])),
        chain: Object.fromEntries(gameChain.map((id) => [id, read(id)])),
        script: document.querySelector('script:not([src])').hasAttribute('data-yahagi-isolated'),
        head: document.head.hasAttribute('data-yahagi-isolated'),
        isolatedCount: document.querySelectorAll('[data-yahagi-isolated]').length,
        state: window.__yahagiMobileReadPresentation(),
        messages: window.__messages.slice(),
      };
    }, {pageChrome, gameChain});
    const check = async (name, body) => {
      try {
        await body();
        console.log(`PASS ${name}`);
      } catch (error) {
        failures++;
        console.log(`FAIL ${name}\n${error.stack}`);
      }
    };
    const expectIsolated = (snap, ids) => {
      for (const id of ids) {
        assert.equal(snap.chrome[id].isolated, true, `${id} must be isolated`);
        assert.equal(snap.chrome[id].display, 'none', `${id} must not render`);
      }
    };
    const expectChainVisible = (snap) => {
      for (const [id, value] of Object.entries(snap.chain)) {
        assert.equal(value.isolated, false, `${id} carries the game and must stay`);
        assert.notEqual(value.display, 'none', `${id} must render`);
      }
    };

    await check('game state isolates every sibling along the frame ancestry', async () => {
      assert.equal(await page.evaluate(source), 'game');
      await settle();
      const snap = await snapshot();
      expectIsolated(snap, pageChrome);
      expectChainVisible(snap);
      assert.equal(snap.script, false, 'Unrendered elements are left alone');
      assert.equal(snap.head, false, 'The document head is left alone');
      assert.equal(snap.isolatedCount, pageChrome.length);
    });

    await check('reinjection keeps the same isolation', async () => {
      await page.evaluate(source);
      await page.evaluate(source);
      await settle();
      const snap = await snapshot();
      expectIsolated(snap, pageChrome);
      assert.equal(snap.isolatedCount, pageChrome.length);
    });

    await check('content added later is isolated by the presentation observer', async () => {
      await page.evaluate(() => {
        const late = document.createElement('div');
        late.id = 'late';
        late.textContent = 'late banner';
        document.getElementById('shell').appendChild(late);
      });
      await settle();
      assert.equal(await page.evaluate(() => document.getElementById('late').hasAttribute('data-yahagi-isolated')), true);
    });

    await check('a dialog opened inside isolated content switches to web and restores the page', async () => {
      await page.evaluate(() => { window.__messages.length = 0; document.getElementById('dialog').show(); });
      await settle();
      const snap = await snapshot();
      assert.equal(snap.state, 'web');
      assert.ok(snap.messages.includes('web'), 'The bridge must hear the web state');
      assert.equal(snap.isolatedCount, 0, 'Web mode releases every isolated element');
      assert.notEqual(snap.chrome.header.display, 'none');
    });

    await check('closing the dialog isolates the page again', async () => {
      await page.evaluate(() => { window.__messages.length = 0; document.getElementById('dialog').close(); });
      await settle();
      const snap = await snapshot();
      assert.equal(snap.state, 'game');
      assert.ok(snap.messages.includes('game'));
      expectIsolated(snap, pageChrome);
    });

    await check('a modal dialog opened inside isolated content becomes reachable', async () => {
      await page.evaluate(() => document.getElementById('dialog').showModal());
      await settle();
      const snap = await snapshot();
      assert.equal(snap.state, 'web');
      assert.equal(await page.evaluate(() => getComputedStyle(document.getElementById('dialog')).display), 'block');
      await page.evaluate(() => document.getElementById('dialog').close());
      await settle();
      assert.equal((await snapshot()).state, 'game');
    });

    await check('an ARIA modal keeps its branch while the rest stays isolated', async () => {
      await page.evaluate(() => {
        const modal = document.createElement('div');
        modal.setAttribute('aria-modal', 'true');
        modal.textContent = 'purchase';
        document.getElementById('aria-host').appendChild(modal);
      });
      await settle();
      const snap = await snapshot();
      assert.equal(snap.state, 'game');
      assert.equal(snap.chrome['aria-host'].isolated, false);
      assert.notEqual(snap.chrome['aria-host'].display, 'none');
      expectIsolated(snap, pageChrome.filter((id) => id !== 'aria-host'));
      await page.evaluate(() => document.getElementById('aria-host').replaceChildren());
      await settle();
      expectIsolated(await snapshot(), pageChrome);
    });

    await check('runtime disposal releases isolation', async () => {
      await page.evaluate(() => window.__yahagiMobileDisposePresentation());
      const snap = await snapshot();
      assert.equal(snap.isolatedCount, 0);
      assert.notEqual(snap.chrome.footer.display, 'none');
    });
  } finally {
    await browser.close();
  }
  console.log(failures === 0 ? 'Game page isolation passed' : `${failures} isolation check(s) failed`);
  process.exitCode = failures === 0 ? 0 : 1;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
