// Run with: node --test tool/test_game_frame_rate_script.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {test} = require('node:test');
const folder = path.join(__dirname, '../android/app/src/main/kotlin/app/yahagi/kancollebrowser/browser');
const sourceFile = fs.existsSync(path.join(folder, 'GameFrameRateBridgeScript.kt'))
  ? 'GameFrameRateBridgeScript.kt' : 'GameFrameRateBridge.kt';
const source = fs.readFileSync(path.join(folder, sourceFile), 'utf8').split('"""')[1];
const tickerSource = fs.readFileSync(path.join(__dirname, 'fixtures/createjs-ticker-0.6.2.js'), 'utf8');

function frame({pixi = true, pathname = '/kcs2/index.php', canvasFirst = true, initialFps = 60} = {}) {
  let now = 1000, id = 0, ticks = 0, draws = 0, offscreen = 0, otherDraws = 0;
  const raf = new Map(), timers = new Map(), events = new Map(), messages = [];
  const canvas = {nodeName: 'CANVAS', width: 1200, height: 720, isConnected: true};
  const otherCanvas = {nodeName: 'CANVAS', width: 24, height: 24, isConnected: true};
  const document = {
    hidden: false, visibilityState: 'visible',
    querySelector: () => canvasFirst ? canvas : null,
    querySelectorAll: () => canvasFirst ? [canvas] : [],
    addEventListener: (name, fn) => events.set(name, fn),
    removeEventListener: (name, fn) => {if (events.get(name) === fn) events.delete(name);},
  };
  const channel = {postMessage: text => messages.push(JSON.parse(text))};
  function Renderer(view = canvas) {this.view = view;}
  const originalRender = Renderer.prototype.render = function(stage, texture) {
    if (texture != null) offscreen++; else if (this.view === canvas) draws++; else otherDraws++;
    now += 0.2;
    return 'rendered';
  };
  const context = {
    console, document, location: {pathname}, performance: {now: () => now},
    YahagiFrameRate: channel,
    requestAnimationFrame(fn) {const key = ++id; raf.set(key, fn); return key;},
    cancelAnimationFrame(key) {raf.delete(key);},
    setInterval(fn, ms) {const key = ++id; timers.set(key, {fn, ms, next: now + ms, repeat: true}); return key;},
    clearInterval(key) {timers.delete(key);},
    setTimeout(fn, ms) {const key = ++id; timers.set(key, {fn, ms, next: now + ms}); return key;},
    clearTimeout(key) {timers.delete(key);},
    addEventListener: (name, fn) => events.set(name, fn),
    removeEventListener: (name, fn) => {if (events.get(name) === fn) events.delete(name);},
  };
  context.window = context;
  if (pixi) context.PIXI = {VERSION: '4.8.8', WebGLRenderer: Renderer, CanvasRenderer: class CanvasRenderer extends Renderer {}};
  vm.createContext(context);
  vm.runInContext(tickerSource, context);
  const ticker = context.createjs.Ticker;
  ticker.framerate = initialFps;
  const originalSynch = ticker._handleSynch, originalRAF = ticker._handleRAF;
  const originalSetup = ticker._setupTick, originalTick = ticker._tick;
  vm.runInContext(source, context);
  const renderer = new Renderer();
  const send = target => channel.onmessage({data: JSON.stringify({target})});
  const listen = () => ticker.addEventListener('tick', () => ticks++);
  listen();
  const run = (hz, seconds, render = true) => {
    const base = now;
    for (let index = 1; index <= hz * seconds; index++) {
      now = base + index * 1000 / hz;
      const callbacks = [...raf.values()]; raf.clear();
      for (const callback of callbacks) callback(now);
      // Browser timers due in this simulation run once, never catch up in loops.
      for (const [key, timer] of [...timers]) if (now >= timer.next) {
        if (timer.repeat) timer.next = now + timer.ms; else timers.delete(key);
        timer.fn();
      }
      if (render) renderer.render({});
    }
  };
  return {
    context, ticker, renderer, Renderer, canvas, otherCanvas, document, channel, messages, raf, timers,
    originalSynch, originalRAF, originalSetup, originalTick, originalRender, send, run, listen,
    counts: () => ({ticks, draws, offscreen, otherDraws}),
    advance(ms) {now += ms;},
    sample() {for (const timer of [...timers.values()]) if (timer.repeat) timer.fn(); return messages.filter(m => m.kind === 'sample').at(-1);},
    visible(value) {document.hidden = !value; document.visibilityState = value ? 'visible' : 'hidden'; events.get('visibilitychange')?.();},
  };
}

for (const target of [30, 60]) for (const hz of [60, 80, 90, 120, 144, 165]) {
  test(target + ' tick/render cap accumulates cadence at ' + hz + ' Hz', () => {
    const f = frame(); f.send('fps' + target); f.run(hz, 4);
    const {ticks, draws} = f.counts();
    assert.ok(Math.abs(ticks - 4 * target) <= 2, 'ticks=' + ticks);
    assert.ok(Math.abs(draws - 4 * target) <= 2, 'draws=' + draws);
    const sample = f.sample();
    assert.equal(sample.configuredFps, target);
    assert.ok(sample.renderFps > target - 3 && sample.renderFps < target + 3);
    assert.ok(sample.rafFps > hz - 3 && sample.rafFps < hz + 3);
  });
}

test('offscreen textures and other canvases are never discarded', () => {
  const f = frame(); f.send('fps30');
  assert.equal(f.renderer.render({}), 'rendered');
  f.renderer.render({});
  for (let n = 0; n < 20; n++) assert.equal(f.renderer.render({}, {}), 'rendered');
  const other = new f.Renderer(f.otherCanvas);
  for (let n = 0; n < 20; n++) assert.equal(other.render({}), 'rendered');
  assert.equal(f.counts().draws, 1); assert.equal(f.counts().offscreen, 20); assert.equal(f.counts().otherDraws, 20);
});

test('high refresh normalizes the 60 baseline and keeps the original RAF handler', () => {
  const f = frame(); f.send('fps30'); f.run(120, 1);
  f.send('highRefresh');
  assert.ok(Math.abs(f.ticker.framerate - 60) < 0.001);
  assert.equal(f.ticker._handleRAF, f.originalRAF);
  const before = f.counts(); f.run(120, 2); const after = f.counts();
  assert.ok(after.ticks - before.ticks >= 239);
  assert.equal(after.draws - before.draws, 240);
});

test('game-requested 15 fps remains an intentional slowdown', () => {
  const f = frame(); f.send('fps60'); f.run(120, 1);
  f.ticker.setFPS(15); f.sample();
  assert.ok(Math.abs(f.ticker.framerate - 15) < 0.001);
  const before = f.counts(); f.run(120, 2);
  assert.ok(Math.abs(f.counts().ticks - before.ticks - 30) <= 1);
  assert.equal(f.sample().configuredFps, 15);
});

test('repeat installation and disposal preserve source methods and remove owned work', () => {
  const f = frame(); vm.runInContext(source, f.context);
  assert.equal(f.messages.filter(m => m.kind === 'ready').length, 1);
  assert.equal([...f.timers.values()].filter(t => t.repeat).length, 1);
  assert.equal(f.ticker._setupTick, f.originalSetup); assert.equal(f.ticker._tick, f.originalTick);
  assert.equal(typeof f.context.__yahagiFrameRateRuntime?.dispose, 'function');
  f.context.__yahagiFrameRateRuntime.dispose();
  assert.equal(f.ticker._handleSynch, f.originalSynch);
  assert.equal(f.Renderer.prototype.render, f.originalRender);
  assert.equal([...f.timers.values()].filter(t => t.repeat).length, 0);
  vm.runInContext(source, f.context);
  assert.equal([...f.timers.values()].filter(t => t.repeat).length, 1);
});

test('hidden stops the meter and resume resets gaps without burst ticks or renders', () => {
  const f = frame(); f.send('fps60'); f.run(120, 1);
  const activeRAF = f.raf.size;
  f.visible(false); assert.equal(f.raf.size, activeRAF - 1);
  f.advance(10000); assert.equal(f.sample().visible, false);
  f.visible(true); const before = f.counts(); f.run(120, 1 / 120);
  assert.ok(f.counts().ticks - before.ticks <= 1); assert.equal(f.counts().draws - before.draws, 1);
  f.run(120, 1); const sample = f.sample();
  assert.ok(sample.renderP99Ms < 50); assert.equal(sample.visible, true);
});

test('missing PIXI reports missing instrumentation rather than zero render fps', () => {
  const f = frame({pixi: false}); f.run(60, 2, false); const sample = f.sample();
  assert.equal(sample.renderFps, null); assert.equal(sample.renderFrames, null);
  assert.equal(sample.renderP95Ms, null); assert.equal(sample.rafFps, null);
});

test('ticker reset preserves pacing and fresh target changes take effect', () => {
  const f = frame(); f.send('fps30'); f.run(90, 1);
  f.ticker.reset(); f.listen(); f.sample(); f.send('fps60');
  const before = f.counts(); f.run(90, 2);
  assert.ok(Math.abs(f.counts().ticks - before.ticks - 120) <= 1);
  assert.ok(Math.abs(f.counts().draws - before.draws - 120) <= 1);
});

test('no compatible private scheduler falls back without replacing public callbacks', () => {
  const f = frame(); f.context.__yahagiFrameRateRuntime?.dispose();
  f.ticker._handleSynch = undefined; vm.runInContext(source, f.context); f.send('fps60');
  assert.equal(f.ticker.timingMode, f.ticker.TIMEOUT);
  assert.equal(f.ticker._tick, f.originalTick);
});

test('explicit target changes apply the new cap after a game-requested slowdown', () => {
  const f = frame(); f.send('fps60'); f.ticker.setFPS(15); f.sample();
  f.send('fps30');
  assert.ok(Math.abs(f.ticker.framerate - 30) < 0.001);
});

test('a 30 fps boot receives the initial 60 fps target', () => {
  const f = frame({initialFps: 30});
  assert.ok(Math.abs(f.ticker.framerate - 60) < 0.001);
});

test('disposal restores the original configuration while preserving a game-owned slowdown', () => {
  const f = frame(); f.send('fps30'); f.context.__yahagiFrameRateRuntime.dispose();
  assert.ok(Math.abs(f.ticker.framerate - 60) < 0.001);
  assert.equal(f.ticker.timingMode, null);
  const slow = frame(); slow.send('fps60'); slow.ticker.setFPS(15);
  slow.context.__yahagiFrameRateRuntime.dispose();
  assert.ok(Math.abs(slow.ticker.framerate - 15) < 0.001);
});

test('late PIXI and canvas enable instrumentation without adding a second interval', () => {
  const f = frame({pixi: false}); f.run(90, 2, false);
  assert.equal(f.sample().renderFps, null);
  f.context.PIXI = {VERSION: '4.8.8', WebGLRenderer: f.Renderer};
  f.sample(); f.run(90, 2);
  assert.ok(f.sample().renderFps > 57);
  assert.equal([...f.timers.values()].filter(t => t.repeat).length, 1);
});

test('a ticker that appears after installation receives the pending target', () => {
  const f = frame(); f.context.__yahagiFrameRateRuntime.dispose();
  const createjs = f.context.createjs;
  delete f.context.createjs; vm.runInContext(source, f.context); f.send('fps30');
  f.context.createjs = createjs; f.sample();
  const before = f.counts(); f.run(90, 2);
  assert.ok(Math.abs(f.counts().ticks - before.ticks - 60) <= 1);
});

test('read-only snapshot reports only actual onscreen calls after the cap', () => {
  const f = frame(); f.send('fps30'); f.run(120, 2);
  assert.equal(typeof f.context.__yahagiFrameRateRuntime?.getSnapshot, 'function');
  const snapshot = f.context.__yahagiFrameRateRuntime.getSnapshot();
  assert.ok(Number.isFinite(snapshot.sampledAtMs));
  assert.ok(snapshot.renderFrames >= 29 && snapshot.renderFrames <= 31);
  snapshot.renderFrames = -1;
  assert.ok(f.context.__yahagiFrameRateRuntime.getSnapshot().renderFrames >= 29);
});

test('later renderer wrappers do not make periodic refresh apply the cap twice', () => {
  const f = frame(); f.send('fps60');
  const ours = f.Renderer.prototype.render;
  f.Renderer.prototype.render = function() {return ours.apply(this, arguments);};
  f.sample(); const before = f.counts(); f.run(120, 2);
  assert.ok(Math.abs(f.counts().draws - before.draws - 120) <= 1);
});

test('long visible stalls resume with at most one tick and one draw', () => {
  const f = frame(); f.send('fps30'); f.run(120, 1); f.advance(15000);
  const before = f.counts(); f.run(120, 1 / 120); const after = f.counts();
  assert.equal(after.ticks - before.ticks, 1); assert.equal(after.draws - before.draws, 1);
});

test('outer documents never start canvas instrumentation or the meter', () => {
  const f = frame({pathname: '/gadget_html5/'}); f.run(120, 2);
  assert.equal(f.counts().draws, 240); f.sample();
  assert.equal(f.messages.filter(message => message.kind === 'sample').length, 0);
});
