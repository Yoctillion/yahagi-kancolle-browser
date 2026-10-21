// Run with node --test test/subtitles/ship_subtitles_runtime_test.cjs.
// PLAYWRIGHT_MODULE / CHROMIUM_EXECUTABLE can select an existing local runtime.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
let browser;
const sourcePath = path.resolve(__dirname, '../../assets/scripts/ship_subtitles.js');
const file = (id, n) => ((id + 7) * 17 * [2475, 6547][n - 1]) % 99173 + 100000;
const voice = (id, n) => `https://w01.kancolle-server.com/kcs/sound/kcship${id}/${file(id, n)}.mp3?version=1`;

before(async () => {
  const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
  browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROMIUM_EXECUTABLE || (fs.existsSync(edge) ? edge : undefined),
    args: ['--no-sandbox'],
  });
});
after(async () => { if (browser) await browser.close(); });

async function pageFor(url = 'https://w01.kancolle-server.com/kcs2/index.php', options = {}) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, ...options });
  await page.route('**/*', route => route.fulfill({ body: '<!doctype html><html><body style="margin:0"><canvas width="1200" height="720" style="width:100%;height:720px"></canvas></body></html>', contentType: 'text/html' }));
  await page.goto(url);
  await prepareRuntime(page);
  return page;
}
async function prepareRuntime(page) {
  await page.evaluate(() => {
    window.messages = [];
    window.YahagiShipSubtitles = { postMessage: text => window.messages.push(JSON.parse(text)) };
    window.Howler = { _howls: [] };
    window.Howl = class {
      constructor(src) { this._src = src; this.events = {}; this._sounds = []; window.Howler._howls.push(this); }
      on(event, callback) { (this.events[event] ||= []).push(callback); return this; }
      off(event, callback) { this.events[event] = (this.events[event] || []).filter(x => x !== callback); return this; }
      play() { return 1; } // Calling play is not evidence that audio actually started.
      unload() { window.Howler._howls = window.Howler._howls.filter(howl => howl !== this); this.unloaded = true; return this; }
      duration() { return 2; }
      emit(event, id = 1) { for (const callback of this.events[event] || []) callback(id); }
    };
    window.originalPlay = window.Howl.prototype.play;
    window.originalUnload = window.Howl.prototype.unload;
  });
  const source = fs.existsSync(sourcePath) ? fs.readFileSync(sourcePath, 'utf8') : '// Runtime has not been implemented yet.';
  await page.addScriptTag({ content: source });
}
async function embeddedGame() {
  const page = await browser.newPage({ isMobile: true, viewport: { width: 360, height: 640 }, deviceScaleFactor: 3 });
  await page.route('**/*', route => route.fulfill({ contentType: 'text/html', body: route.request().url().includes('www.dmm.com')
    ? '<!doctype html><meta name="viewport" content="width=1200"><body style="margin:0"><iframe style="border:0;width:1200px;height:720px" src="https://w01.kancolle-server.com/kcs2/index.php"></iframe></body>'
    : '<!doctype html><body style="margin:0"><canvas width="1200" height="720" style="width:1200px;height:720px"></canvas></body>' }));
  await page.goto('https://www.dmm.com/kancolle');
  const frame = page.frames().find(frame => frame.url().includes('/kcs2/'));
  await prepareRuntime(frame);
  return { page, frame, displayScale: await page.evaluate(() => visualViewport.scale) };
}
async function send(page, message) {
  await page.evaluate(message => window.YahagiShipSubtitles.onmessage?.({ data: JSON.stringify(message) }), message);
}
async function enable(page, config = {}) {
  await send(page, { kind: 'ships', ships: [{ id: 1, fileName: 'ship1', name: '睦月' }, { id: 1501, fileName: 'ship1501', name: '新舰改' }] });
  await send(page, { kind: 'catalog', version: 'test', quotes: { 1: { 1: '你好，提督！', 2: '这是第二句。', 141: '特殊台词' }, 1501: { 1: '新舰台词。' } } });
  await send(page, { kind: 'config', enabled: true, locked: true, fontSize: 'medium', x: .5, y: .9, ...config });
}
async function play(page, src, name = 'audio') {
  await page.evaluate(({ src, name }) => { window[name] = new window.Howl(src); window[name].play(); }, { src, name });
}
const line = page => page.locator('[data-yahagi-ship-subtitle="text"]').textContent();

async function instrumentWork(page) {
  await page.evaluate(() => {
    window.subtitleWork = { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 };
    const bounds = Element.prototype.getBoundingClientRect;
    Element.prototype.getBoundingClientRect = function () {
      if (this.tagName === 'CANVAS' || this.hasAttribute('data-yahagi-ship-subtitle')) window.subtitleWork.geometryReads++;
      return bounds.apply(this, arguments);
    };
    const measure = CanvasRenderingContext2D.prototype.measureText;
    CanvasRenderingContext2D.prototype.measureText = function () { window.subtitleWork.textMeasurements++; return measure.apply(this, arguments); };
    for (const name of ['setTimeout', 'setInterval']) {
      const original = window[name];
      window[name] = function (callback, delay, ...args) {
        return original(function (...values) { window.subtitleWork.timerCallbacks++; return callback(...values); }, delay, ...args);
      };
    }
  });
}
async function resetWork(page) {
  await page.evaluate(() => Object.keys(window.subtitleWork).forEach(key => { window.subtitleWork[key] = 0; }));
}

test('ready audio hooks stay idle without recurring timer wakeups or geometry work', async () => {
  const page = await pageFor();
  await instrumentWork(page);
  await enable(page);
  await page.waitForTimeout(80); // Let initial ResizeObserver notifications settle.
  await resetWork(page);
  await page.waitForTimeout(1200);
  const work = await page.evaluate(() => window.subtitleWork);
  assert.deepEqual(work, { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 });
  await page.close();
});

test('hidden startup suspends hook probes and resumes late Howler discovery when shown', async () => {
  const page = await pageFor();
  await instrumentWork(page);
  await page.evaluate(() => {
    window.savedHowl = window.Howl; window.savedHowler = window.Howler;
    delete window.Howl; delete window.Howler;
  });
  await enable(page);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await resetWork(page);
  await page.waitForTimeout(1200);
  assert.deepEqual(await page.evaluate(() => window.subtitleWork), { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 });
  await page.evaluate(() => {
    window.Howl = window.savedHowl; window.Howler = window.savedHowler;
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => false });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '睦月：你好，提督！');
  await page.close();
});

test('late Howler startup is discovered automatically, then its backoff timer stops', async () => {
  const page = await pageFor();
  await instrumentWork(page);
  await page.evaluate(() => {
    window.savedHowl = window.Howl; window.savedHowler = window.Howler;
    delete window.Howl; delete window.Howler;
  });
  await enable(page);
  await page.waitForTimeout(300);
  await page.evaluate(() => { window.Howl = window.savedHowl; window.Howler = window.savedHowler; });
  await page.waitForFunction(() => window.Howl.prototype.play !== window.originalPlay);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '睦月：你好，提督！');
  await page.evaluate(() => window.audio.emit('pause'));
  await resetWork(page);
  await page.waitForTimeout(1200);
  assert.deepEqual(await page.evaluate(() => window.subtitleWork), { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 });
  await page.close();
});

test('slow Howler startup is still discovered within one second after several probes', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    window.savedHowl = window.Howl; window.savedHowler = window.Howler;
    delete window.Howl; delete window.Howler;
  });
  await enable(page);
  await page.waitForTimeout(4000);
  await page.evaluate(() => { window.Howl = window.savedHowl; window.Howler = window.savedHowler; });
  await page.waitForTimeout(1000);
  assert.equal(await page.evaluate(() => window.Howl.prototype.play !== window.originalPlay), true);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '睦月：你好，提督！');
  await page.close();
});

test('idle locked captions do no geometry work on scroll or viewport notifications', async () => {
  const page = await pageFor();
  await instrumentWork(page);
  await enable(page);
  await page.waitForTimeout(80);
  await resetWork(page);
  await page.evaluate(() => {
    for (let i = 0; i < 10; i++) {
      window.dispatchEvent(new Event('scroll'));
      window.dispatchEvent(new Event('resize'));
    }
  });
  assert.deepEqual(await page.evaluate(() => window.subtitleWork), { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 });
  await page.close();
});

test('dragging repositions the active caption without repeating character measurements', async () => {
  const page = await pageFor();
  await instrumentWork(page);
  await enable(page, { locked: false });
  await send(page, { kind: 'catalog', quotes: { 1: { 1: '这是一段需要分页显示的长台词。'.repeat(30) } } });
  await play(page, voice(1, 1));
  await page.evaluate(() => { window.audio.duration = () => 100; window.audio.emit('play'); });
  const box = await page.locator('[data-yahagi-ship-subtitle="handle"]').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await resetWork(page);
  await page.mouse.move(300, 200, { steps: 20 });
  await page.mouse.up();
  assert.equal(await page.evaluate(() => window.subtitleWork.textMeasurements), 0);
  assert.ok(await page.evaluate(() => window.messages.some(message => message.kind === 'position')));
  await page.close();
});

test('page transitions reuse measured pages until the caption font or width changes', async () => {
  const page = await pageFor(undefined, { viewport: { width: 400, height: 800 } });
  await instrumentWork(page);
  await enable(page, { fontSize: 'large' });
  await send(page, { kind: 'catalog', quotes: { 1: { 1: '这是一段需要分页显示的长台词。'.repeat(20) } } });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  const first = await line(page);
  await resetWork(page);
  await page.waitForFunction(first => document.querySelector('[data-yahagi-ship-subtitle="text"]').textContent !== first, first);
  assert.equal(await page.evaluate(() => window.subtitleWork.textMeasurements), 0);
  await send(page, { kind: 'config', enabled: true, locked: true, fontSize: 'small' });
  assert.ok(await page.evaluate(() => window.subtitleWork.textMeasurements > 0));
  await page.close();
});

test('unloading a voice releases owned listeners immediately and clears its caption', async () => {
  const page = await pageFor();
  await enable(page);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '睦月：你好，提督！');
  assert.equal(await page.evaluate(() => window.audio.unload() === window.audio), true);
  assert.equal(await page.evaluate(() => Object.values(window.audio.events).flat().length), 0);
  assert.equal(await line(page), '');
  await send(page, { kind: 'config', enabled: false });
  assert.equal(await page.evaluate(() => window.Howl.prototype.unload === window.originalUnload), true);
  await page.close();
});

test('a replaced game canvas updates overlay bounds without recurring canvas scans', async () => {
  const page = await pageFor();
  await enable(page, { locked: false, x: .75, y: .75 });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  await page.evaluate(() => {
    const replacement = document.createElement('canvas');
    replacement.width = 600; replacement.height = 400;
    replacement.style.cssText = 'position:absolute;left:100px;top:50px;width:600px;height:400px';
    document.querySelector('canvas').replaceWith(replacement);
  });
  await page.waitForTimeout(80);
  const box = await page.locator('[data-yahagi-ship-subtitle="root"]').boundingBox();
  assert.ok(Math.abs(box.x + box.width / 2 - 550) < 1);
  assert.ok(Math.abs(box.y + box.height / 2 - 350) < 1);
  await page.close();
});

test('a larger canvas shown later becomes the overlay bounds without polling', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    document.querySelector('canvas').style.cssText = 'width:600px;height:400px';
    const second = document.createElement('canvas');
    second.id = 'second';
    second.style.cssText = 'position:absolute;left:0;top:0;width:1000px;height:600px;display:none';
    document.body.appendChild(second);
  });
  await enable(page, { locked: false, x: .75, y: .75 });
  await page.waitForTimeout(80);
  const root = page.locator('[data-yahagi-ship-subtitle="root"]');
  const before = await root.boundingBox();
  assert.ok(Math.abs(before.x + before.width / 2 - 450) < 1);
  await page.evaluate(() => { document.querySelector('#second').style.display = 'block'; });
  await page.waitForTimeout(80);
  const after = await root.boundingBox();
  assert.ok(Math.abs(after.x + after.width / 2 - 750) < 1);
  assert.ok(Math.abs(after.y + after.height / 2 - 450) < 1);
  await page.close();
});

test('removed canvas candidates are released from resize observation', async () => {
  const page = await pageFor();
  await page.evaluate(() => {
    window.resizeTargets = new Set();
    const Observer = window.ResizeObserver;
    window.ResizeObserver = class extends Observer {
      observe(target, ...args) { window.resizeTargets.add(target); return super.observe(target, ...args); }
      disconnect() { window.resizeTargets.clear(); return super.disconnect(); }
    };
    const small = document.createElement('canvas');
    small.id = 'small'; small.style.cssText = 'width:100px;height:100px';
    document.body.appendChild(small);
    window.smallCanvas = small;
  });
  await enable(page);
  await page.waitForTimeout(80);
  assert.equal(await page.evaluate(() => window.resizeTargets.has(window.smallCanvas)), true);
  await page.evaluate(() => window.smallCanvas.remove());
  await page.waitForTimeout(80);
  assert.equal(await page.evaluate(() => window.resizeTargets.has(window.smallCanvas)), false);
  assert.equal(await page.evaluate(() => window.resizeTargets.has(document.querySelector('canvas'))), true);
  await page.close();
});

test('document-start config attaches the unlocked handle and canvas observer when DOM becomes ready', async () => {
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
  await page.route('**/*', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><body style="margin:0"><canvas style="width:1200px;height:720px"></canvas></body>' }));
  await page.addInitScript({ content: `
    window.Howler = { _howls: [] };
    window.Howl = class { play() {} };
    window.YahagiShipSubtitles = { postMessage(value) {
      if (JSON.parse(value).kind !== 'ready') return;
      window.configBeforeRoot = document.documentElement === null;
      window.YahagiShipSubtitles.onmessage({ data: {
        kind: 'config', enabled: true, locked: false, fontSize: 'medium', x: .75, y: .75
      } });
    } };
    ${fs.readFileSync(sourcePath, 'utf8')}
  ` });
  await page.goto('https://w01.kancolle-server.com/kcs2/index.php');
  await page.waitForTimeout(80);
  assert.equal(await page.evaluate(() => window.configBeforeRoot), true, 'The fixture sends config before documentElement exists');
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="handle"]').count(), 1);
  await page.evaluate(() => {
    const replacement = document.createElement('canvas');
    replacement.style.cssText = 'position:absolute;left:100px;top:50px;width:600px;height:400px';
    document.querySelector('canvas').replaceWith(replacement);
  });
  await page.waitForTimeout(80);
  const box = await page.locator('[data-yahagi-ship-subtitle="root"]').boundingBox();
  assert.ok(Math.abs(box.x + box.width / 2 - 550) < 1);
  assert.ok(Math.abs(box.y + box.height / 2 - 350) < 1);
  await page.close();
});

test('only the game frame handshakes; disabled defaults do not hook audio', async () => {
  const page = await pageFor();
  assert.equal(await page.evaluate(() => window.messages[0]?.kind), 'ready');
  assert.equal(await page.evaluate(() => window.Howl.prototype.play === window.originalPlay), true);
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="root"]').count(), 0);
  const other = await pageFor('https://w01.kancolle-server.com/account');
  assert.equal(await other.evaluate(() => window.messages.length), 0);
  await page.close(); await other.close();
});

test('preload and play invocation produce no subtitle; actual play, cached replay, and special IDs do', async () => {
  const page = await pageFor();
  await enable(page);
  await play(page, voice(1, 1));
  assert.equal(await line(page), '');
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '睦月：你好，提督！');
  await page.evaluate(() => window.audio.emit('end'));
  assert.equal(await line(page), '');
  await page.evaluate(() => { window.audio.play(); window.audio.emit('play'); });
  assert.equal(await line(page), '睦月：你好，提督！');
  await play(page, 'https://w01.kancolle-server.com/kcs/sound/kcship1/141.mp3', 'special');
  await page.evaluate(() => window.special.emit('play'));
  assert.equal(await line(page), '睦月：特殊台词');
  await page.close();
});

test('existing Howls attach on enable and new master IDs have no fixed ship cutoff', async () => {
  const page = await pageFor();
  await play(page, voice(1501, 1));
  await enable(page);
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await line(page), '新舰改：新舰台词。');
  await page.close();
});

test('old end events cannot clear a newer sound, while pause and unknown voice clear current text', async () => {
  const page = await pageFor();
  await enable(page);
  await play(page, voice(1, 1), 'first');
  await page.evaluate(() => window.first.emit('play', 1));
  await play(page, voice(1, 2), 'second');
  await page.evaluate(() => { window.second.emit('play', 2); window.first.emit('end', 1); });
  assert.equal(await line(page), '睦月：这是第二句。');
  await page.evaluate(() => window.second.emit('pause', 2));
  assert.equal(await line(page), '');
  await page.evaluate(() => window.first.emit('play', 1));
  await play(page, 'https://w01.kancolle-server.com/kcs/sound/kcship1/999999.mp3', 'missing');
  await page.evaluate(() => window.missing.emit('play'));
  assert.equal(await line(page), '');
  await page.close();
});

test('text passes clicks through; only unlocked handle captures dragging and persists normalized position', async () => {
  const page = await pageFor();
  await enable(page, { locked: false });
  await play(page, voice(1, 1));
  await page.evaluate(() => { window.audio.emit('play'); window.canvasClicks = 0; document.querySelector('canvas').onclick = () => window.canvasClicks++; });
  const textBox = await page.locator('[data-yahagi-ship-subtitle="text"]').boundingBox();
  await page.mouse.click(textBox.x + textBox.width / 2, textBox.y + textBox.height / 2);
  assert.equal(await page.evaluate(() => window.canvasClicks), 1);
  const handle = page.locator('[data-yahagi-ship-subtitle="handle"]');
  const box = await handle.boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down(); await page.mouse.move(250, 200); await page.mouse.up();
  const position = await page.evaluate(() => window.messages.findLast(x => x.kind === 'position'));
  assert.ok(position?.x > 0 && position.x < .5);
  assert.ok(position?.y > 0 && position.y < .5);
  const rootBefore = await page.locator('[data-yahagi-ship-subtitle="root"]').boundingBox();
  await page.setViewportSize({ width: 600, height: 800 });
  await page.waitForTimeout(80);
  const rootAfter = await page.locator('[data-yahagi-ship-subtitle="root"]').boundingBox();
  assert.ok(Math.abs((rootAfter.x + rootAfter.width / 2) / 600 - (rootBefore.x + rootBefore.width / 2) / 1200) < .02);
  await send(page, { kind: 'config', enabled: true, locked: true, fontSize: 'large', x: position.x, y: position.y });
  assert.equal(await handle.count(), 0);
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="text"]').evaluate(x => getComputedStyle(x).pointerEvents), 'none');
  await page.close();
});

test('disable restores owned wrappers, removes overlay and prevents late play events', async () => {
  const page = await pageFor();
  await enable(page, { locked: false });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  await send(page, { kind: 'config', enabled: false });
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="root"]').count(), 0);
  assert.equal(await page.evaluate(() => window.Howl.prototype.play === window.originalPlay), true);
  assert.equal(await page.evaluate(() => Object.values(window.audio.events).flat().length), 0);
  await page.evaluate(() => window.audio.emit('play'));
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="root"]').count(), 0);
  await page.close();
});

test('small, medium and large remain distinct on a phone; hidden documents clear and pagehide stops hooks', async () => {
  const page = await pageFor();
  await page.setViewportSize({ width: 400, height: 800 });
  await enable(page);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  const sizes = [];
  for (const fontSize of ['small', 'medium', 'large']) {
    await send(page, { kind: 'config', enabled: true, locked: true, fontSize });
    sizes.push(await page.locator('[data-yahagi-ship-subtitle="text"]').evaluate(x => parseFloat(getComputedStyle(x).fontSize)));
  }
  assert.ok(sizes[0] < sizes[1] && sizes[1] < sizes[2], `Expected ascending font sizes; got ${sizes}`);
  await page.evaluate(() => {
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  assert.equal(await line(page), '');
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
  assert.equal(await page.locator('[data-yahagi-ship-subtitle="root"]').count(), 0);
  assert.equal(await page.evaluate(() => window.Howl.prototype.play === window.originalPlay), true);
  await page.close();
});

test('desktop game viewport scaled onto a phone preserves readable physical font sizes', async () => {
  const page = await pageFor(undefined, { viewport: { width: 400, height: 800 }, isMobile: true });
  await enable(page);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  const measurements = [];
  for (const fontSize of ['small', 'medium', 'large']) {
    await send(page, { kind: 'config', enabled: true, locked: true, fontSize });
    measurements.push(await page.locator('[data-yahagi-ship-subtitle="text"]').evaluate(x => ({
      scale: visualViewport.scale,
      displayed: parseFloat(getComputedStyle(x).fontSize) * visualViewport.scale,
    })));
  }
  assert.ok(measurements[0].scale < .6, 'Fixture must exercise a scaled desktop viewport');
  assert.ok(measurements[0].displayed >= 11.9, JSON.stringify(measurements));
  assert.ok(measurements[1].displayed >= 14.9, JSON.stringify(measurements));
  assert.ok(measurements[2].displayed >= 18.9, JSON.stringify(measurements));
  await page.close();
});

test('dragging after a long line clamps at the edge starts from the visible handle without a dead zone', async () => {
  const page = await pageFor();
  await enable(page, { locked: false, x: .01, y: .5 });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  const root = page.locator('[data-yahagi-ship-subtitle="root"]');
  const before = await root.boundingBox();
  const box = await page.locator('[data-yahagi-ship-subtitle="handle"]').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 30, box.y + box.height / 2);
  await page.mouse.up();
  const after = await root.boundingBox();
  assert.ok(after.x - before.x >= 29, `Expected immediate 30px movement, got ${after.x - before.x}`);
  await page.close();
});

test('native displayScale keeps fonts readable in a real cross-origin scaled iframe', async () => {
  const { page, frame, displayScale } = await embeddedGame();
  assert.equal(await frame.evaluate(() => visualViewport.scale), 1);
  assert.ok(displayScale < .31 && displayScale > .29);
  await enable(frame, { displayScale });
  await play(frame, voice(1, 1));
  await frame.evaluate(() => window.audio.emit('play'));
  for (const [fontSize, minimum] of [['small', 12], ['medium', 15], ['large', 19]]) {
    await send(frame, { kind: 'config', enabled: true, locked: true, fontSize, displayScale });
    const css = await frame.locator('[data-yahagi-ship-subtitle="text"]').evaluate(x => parseFloat(getComputedStyle(x).fontSize));
    assert.ok(css * displayScale >= minimum - .01, `${fontSize}: ${css * displayScale}`);
  }
  await page.close();
});

test('182-character lines paginate within two lines inside the game and old page timers never restore stopped text', async () => {
  const { page, frame, displayScale } = await embeddedGame();
  await enable(frame, { displayScale, fontSize: 'large' });
  const quote = '提督，今天也请和舰队一起努力。'.repeat(13).slice(0, 182);
  await send(frame, { kind: 'catalog', version: 'long', quotes: { 1: { 1: quote } } });
  await play(frame, voice(1, 1));
  await frame.evaluate(() => window.audio.emit('play'));
  const first = await line(frame);
  assert.ok(first.length < quote.length);
  assert.ok(first.split('\n').length <= 2);
  const canvasBox = await frame.locator('canvas').boundingBox();
  const subtitle = frame.locator('[data-yahagi-ship-subtitle="text"]');
  const box = await subtitle.boundingBox();
  assert.ok(box.height * displayScale < 65, `Two displayed lines must fit: ${box.height * displayScale}`);
  assert.ok(box.y >= canvasBox.y - 1 && box.y + box.height <= canvasBox.y + canvasBox.height + 1);
  await page.waitForTimeout(450);
  assert.notEqual(await line(frame), first);
  await frame.evaluate(() => window.audio.emit('stop'));
  await page.waitForTimeout(450);
  assert.equal(await line(frame), '');
  await page.close();
});

test('a one-character final page is readable before the real audio end and cannot return afterward', async () => {
  const page = await pageFor();
  await enable(page);
  const quote = `${'甲'.repeat(20)}\n${'乙'.repeat(20)}\n尾`;
  await send(page, { kind: 'catalog', quotes: { 1: { 1: quote } } });
  await play(page, voice(1, 1));
  const playback = await page.evaluate(() => new Promise(resolve => {
    const subtitle = document.querySelector('[data-yahagi-ship-subtitle="text"]');
    const pages = [];
    const record = () => {
      if (subtitle.textContent && subtitle.textContent !== pages.at(-1)?.text) {
        pages.push({ text: subtitle.textContent, shownAt: performance.now() });
      }
    };
    const observer = new MutationObserver(record);
    observer.observe(subtitle, { childList: true });
    window.audio.emit('play');
    record();
    // Howler's end is independent of the subtitle's own expiry timer.
    setTimeout(() => {
      const endedAt = performance.now();
      window.audio.emit('end');
      const textAtEnd = subtitle.textContent;
      setTimeout(() => {
        observer.disconnect();
        resolve({ pages, endedAt, textAtEnd, textAfterEnd: subtitle.textContent });
      }, 400);
    }, window.audio.duration() * 1000);
  }));
  assert.equal(playback.pages.length, 2, `Every page must appear before end: ${JSON.stringify(playback)}`);
  assert.equal(playback.pages[1].text, '睦月：尾');
  assert.equal(playback.pages.map(entry => entry.text.slice('睦月：'.length).replace(/\n/g, '')).join(''), quote.replace(/\n/g, ''));
  assert.ok(playback.endedAt - playback.pages[1].shownAt >= 500, `The final page needs reading time: ${JSON.stringify(playback)}`);
  assert.equal(playback.textAtEnd, '', 'End clears the current page immediately');
  assert.equal(playback.textAfterEnd, '', 'Expired page timers cannot restore the caption');
  await page.close();
});

test('missing end events still expire captions and unknown durations retain their bounded fallback', async () => {
  const page = await pageFor();
  await page.clock.install({ time: new Date('2026-10-20T00:00:00Z') });
  await page.clock.pauseAt(new Date('2026-10-20T00:00:01Z'));
  await enable(page);
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  await page.clock.runFor(2000);
  assert.equal(await line(page), '睦月：你好，提督！', 'The known-duration watchdog retains its 300ms grace');
  await page.clock.runFor(300);
  assert.equal(await line(page), '', 'Missing end cannot leave a known-duration caption behind');
  for (const mode of ['zero', 'nan', 'throws']) {
    await page.evaluate(mode => {
      window.audio.duration = () => { if (mode === 'throws') throw new Error('No duration'); return mode === 'zero' ? 0 : NaN; };
      window.audio.emit('play');
    }, mode);
    await page.clock.runFor(2499);
    assert.equal(await line(page), '睦月：你好，提督！', `${mode}: the short-line fallback lasts 2500ms`);
    await page.clock.runFor(1);
    assert.equal(await line(page), '', `${mode}: fallback expiry clears the caption`);
  }
  await page.close();
});

test('catalog switches clear old pages and the same cached voice replays current language as plain text', async () => {
  const page = await pageFor();
  await enable(page);
  await send(page, { kind: 'catalog', version: 'same-upstream-version', quotes: { 1: { 1: '即将切换语言的旧字幕。'.repeat(40) } } });
  await play(page, voice(1, 1));
  await page.evaluate(() => window.audio.emit('play'));
  assert.ok((await line(page)).startsWith('睦月：即将切换语言'));

  const translations = [
    ['zh-CN', '提督，准备出击！<b>前进</b> & 胜利。'],
    ['zh-TW', '提督，準備出擊！<b>前進</b> & 勝利。'],
    ['ja-JP', '提督、出撃の準備はいい？<b>前進</b> & 勝利。'],
    ['en-US', 'Admiral, ready to sortie? <b>Forward</b> & victory.'],
    ['ko-KR', '제독, 출격할 준비 됐나요? <b>전진</b> & 승리!'],
  ];
  for (const [language, quote] of translations) {
    await send(page, { kind: 'catalog', version: 'same-upstream-version', quotes: { 1: { 1: quote } } });
    assert.equal(await line(page), '', `${language}: switching clears the active line`);
    if (language === 'zh-CN') {
      await page.waitForTimeout(450);
      assert.equal(await line(page), '', 'The old paginated line must not return after switching');
    }
    assert.equal(await page.evaluate(() => window.audio.play()), 1, 'The original Howl return value is preserved');
    assert.equal(await line(page), '', 'A cached play invocation alone does not show subtitles');
    await page.evaluate(() => window.audio.emit('play'));
    assert.equal(await line(page), `睦月：${quote}`, `${language}: the cached voice uses the current catalog`);
    assert.equal(await page.locator('[data-yahagi-ship-subtitle="text"] b').count(), 0, `${language}: markup remains plain text`);
  }
  await page.close();
});

for (const [language, quote] of [
  ['zh-TW', '提督，艦隊已經準備好出擊了。請放心將這次作戰交給我們，一定會帶著勝利回來！'.repeat(5)],
  ['ja-JP', '提督、艦隊の出撃準備はできています。今度の作戦も私たちにお任せください、必ず勝利を持ち帰ります！'.repeat(5)],
  ['en-US', 'Admiral, the fleet is ready to sortie. Please leave this operation to us; we will return victorious! '.repeat(5).trim()],
  ['ko-KR', '제독, 함대의 출격 준비가 끝났습니다. 이번 작전도 저희에게 맡겨 주세요. 반드시 승리를 가져오겠습니다! '.repeat(5).trim()],
]) {
  test(`${language} long quotes paginate into two physical lines without losing text or blocking game clicks`, async () => {
    const { page, frame, displayScale } = await embeddedGame();
    await enable(frame, { displayScale, fontSize: 'large' });
    await send(frame, { kind: 'catalog', version: 'multilingual-long', quotes: { 1: { 1: quote } } });
    await frame.evaluate(() => {
      window.canvasClicks = 0;
      document.querySelector('canvas').onclick = () => window.canvasClicks++;
      window.subtitlePages = [];
      const subtitle = document.querySelector('[data-yahagi-ship-subtitle="text"]');
      window.subtitleObserver = new MutationObserver(() => {
        if (!subtitle.textContent) return;
        const style = getComputedStyle(subtitle);
        const box = subtitle.getBoundingClientRect();
        const canvasBox = document.querySelector('canvas').getBoundingClientRect();
        window.subtitlePages.push({
          text: subtitle.textContent,
          height: box.height,
          maximumHeight: parseFloat(style.lineHeight) * 2 + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom),
          fitsCanvas: box.left >= canvasBox.left - 1 && box.right <= canvasBox.right + 1 && box.top >= canvasBox.top - 1 && box.bottom <= canvasBox.bottom + 1,
          pointerEvents: style.pointerEvents,
        });
      });
      window.subtitleObserver.observe(subtitle, { childList: true });
    });
    await play(frame, voice(1, 1));
    await frame.evaluate(() => window.audio.emit('play'));
    const subtitleBox = await frame.locator('[data-yahagi-ship-subtitle="text"]').boundingBox();
    await page.mouse.click(subtitleBox.x + subtitleBox.width / 2, subtitleBox.y + subtitleBox.height / 2);
    assert.equal(await frame.evaluate(() => window.canvasClicks), 1);
    await frame.waitForFunction(() => !document.querySelector('[data-yahagi-ship-subtitle="text"]').textContent);
    const pages = await frame.evaluate(() => window.subtitlePages);
    assert.ok(pages.length > 1, `${language}: the quote must use multiple pages`);
    for (const entry of pages) {
      assert.ok(entry.text.split('\n').length <= 2, `${language}: ${entry.text}`);
      assert.ok(entry.height <= entry.maximumHeight + 1, `${language}: more than two physical lines: ${JSON.stringify(entry)}`);
      assert.equal(entry.fitsCanvas, true, `${language}: every page fits inside the game`);
      assert.equal(entry.pointerEvents, 'none');
    }
    assert.equal(pages.map(entry => entry.text.slice('睦月：'.length).replace(/\n/g, '')).join(''), quote);
    await page.close();
  });
}
