// Controlled Chromium work comparison, not a device power or temperature test.
// node tool/ship_subtitle_browser_benchmark.cjs [runtime-before.js] [runtime-after.js]
const fs = require('node:fs');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const sources = process.argv.slice(2);
if (!sources.length) sources.push('assets/scripts/ship_subtitles.js');
const metricsObject = result => Object.fromEntries(result.metrics.map(metric => [metric.name, metric.value]));
const keys = ['TaskDuration', 'ScriptDuration', 'LayoutDuration', 'LayoutCount', 'RecalcStyleCount'];

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_EXECUTABLE || (fs.existsSync(edge) ? edge : undefined), args: ['--no-sandbox'] });
  try {
    for (const source of sources) {
      const page = await browser.newPage({ viewport: { width: 1200, height: 800 } });
      await page.route('**/*', route => route.fulfill({ contentType: 'text/html', body: '<!doctype html><body style="margin:0"><canvas width="1200" height="720" style="width:1200px;height:720px"></canvas></body>' }));
      await page.goto('https://w01.kancolle-server.com/kcs2/index.php');
      await page.evaluate(() => {
        window.work = { timerCallbacks: 0, geometryReads: 0, textMeasurements: 0 };
        const bounds = Element.prototype.getBoundingClientRect;
        Element.prototype.getBoundingClientRect = function () { window.work.geometryReads++; return bounds.apply(this, arguments); };
        const measure = CanvasRenderingContext2D.prototype.measureText;
        CanvasRenderingContext2D.prototype.measureText = function () { window.work.textMeasurements++; return measure.apply(this, arguments); };
        for (const name of ['setTimeout', 'setInterval']) {
          const original = window[name];
          window[name] = function (callback, delay, ...args) { return original(() => { window.work.timerCallbacks++; callback(...args); }, delay); };
        }
        window.YahagiShipSubtitles = { postMessage() {} };
        window.Howler = { _howls: [] };
        window.Howl = class {
          constructor(src) { this._src = src; this.events = {}; window.Howler._howls.push(this); }
          on(event, callback) { (this.events[event] ||= []).push(callback); return this; }
          off(event, callback) { this.events[event] = (this.events[event] || []).filter(value => value !== callback); return this; }
          play() { return 1; }
          unload() { window.Howler._howls = window.Howler._howls.filter(howl => howl !== this); return this; }
          duration() { return 100; }
          emit(event) { for (const callback of this.events[event] || []) callback(1); }
        };
      });
      await page.addScriptTag({ content: fs.readFileSync(source, 'utf8') });
      const send = message => page.evaluate(message => window.YahagiShipSubtitles.onmessage({ data: message }), message);
      await send({ kind: 'ships', ships: [{ id: 1, fileName: 'ship1', name: '睦月' }] });
      await send({ kind: 'catalog', quotes: { 1: { 1: '这是一段需要分页显示的长台词。'.repeat(30) } } });
      await send({ kind: 'config', enabled: true, locked: true, fontSize: 'medium', x: .5, y: .9 });
      await page.waitForTimeout(100);
      const session = await page.context().newCDPSession(page);
      await session.send('Performance.enable');
      async function sample(action) {
        await page.evaluate(() => Object.keys(window.work).forEach(key => { window.work[key] = 0; }));
        const before = metricsObject(await session.send('Performance.getMetrics'));
        await action();
        const after = metricsObject(await session.send('Performance.getMetrics'));
        return { ...(await page.evaluate(() => window.work)), ...Object.fromEntries(keys.map(key => [key, Number((after[key] - before[key]).toFixed(6))])) };
      }
      const idle = await sample(() => page.waitForTimeout(3200));
      await send({ kind: 'config', enabled: true, locked: false });
      await page.evaluate(() => {
        window.voice = new Howl('https://w01.kancolle-server.com/kcs/sound/kcship1/139081.mp3');
        window.voice.play(); window.voice.emit('play');
      });
      const handle = await page.locator('[data-yahagi-ship-subtitle="handle"]').boundingBox();
      await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2);
      await page.mouse.down();
      const drag = await sample(() => page.mouse.move(300, 200, { steps: 100 }));
      await page.mouse.up();
      await page.evaluate(() => {
        Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
        document.dispatchEvent(new Event('visibilitychange'));
      });
      const hidden = await sample(() => page.waitForTimeout(3200));
      console.log(JSON.stringify({ source, idle, drag, hidden }, null, 2));
      await page.close();
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
