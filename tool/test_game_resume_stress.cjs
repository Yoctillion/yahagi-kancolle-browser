// Deterministic adversarial lifecycle tests against the real retained CreateJS 0.6.2 scheduler.
// No game/account/network resources are loaded. Run: node --test tool/test_game_resume_stress.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {test} = require('node:test');
const fixture = fs.readFileSync(path.join(__dirname, 'test_game_frame_rate_script.cjs'), 'utf8');
const prefix = fixture.slice(0, fixture.indexOf('for (const target of [30, 60])'));
const frame = new Function('require', '__dirname', prefix + '\nreturn frame;')(require, __dirname);
const tickerSource = fs.readFileSync(path.join(__dirname, 'fixtures/createjs-ticker-0.6.2.js'), 'utf8');

function lose(f, current = f.ticker) {
  const id = current._timerId;
  if (current._raf) f.raf.delete(id); else f.timers.delete(id);
  return id;
}
function pauseNative(f, target = 'fps30') {f.send('fps60', false); f.visible(false); f.send(target, false);}
function resumeNative(f, target = 'fps60') {f.send('fps30', true); f.visible(true); f.send(target, true);}

test('automatic background caps preserve a game-owned 15 FPS hit stop through 30 -> 60', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  f.ticker.setFPS(15);
  pauseNative(f);
  assert.ok(Math.abs(f.ticker.framerate - 15) < 0.001, 'background cap must not accelerate the game');
  resumeNative(f); f.run(120, 2);
  assert.ok(Math.abs(f.ticker.framerate - 15) < 0.001, 'foreground cap must not undo game-owned hit stop');
});

test('a lost scheduler waits for a deliberately paused game to unpause before repairing', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); f.ticker.paused = true; lose(f);
  resumeNative(f); const before = f.ticker.getTicks(); f.run(120, 3);
  assert.equal(f.ticker.getTicks(), before); assert.equal(f.ticker.paused, true);
  f.ticker.paused = false; f.run(120, 4);
  assert.ok(f.ticker.getTicks() > before, 'unpausing must not leave the recovered document dead');
});

test('a game that initializes its ticker after foreground delivery can recover its lost initial callback', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); f.ticker.reset(); resumeNative(f);
  f.listen(); lose(f); f.run(120, 4);
  assert.ok(f.ticker.getTicks() > 0, 'late initialized game must receive a gated recovery check');
});

test('game-owned 30 FPS remains observable when it equals the background cap', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); f.ticker.setFPS(30); resumeNative(f); f.run(120, 2);
  assert.ok(Math.abs(f.ticker.framerate - 30) < 0.001);
  f.ticker.setFPS(60); f.run(120, 2);
  assert.ok(Math.abs(f.ticker.framerate - 60) < 0.001, 'the game can end its own slowdown');
});

test('high refresh respects actual game-owned hit-stop ticks and returns to native refresh afterward', () => {
  const f = frame(); f.send('highRefresh', true); f.run(120, 1);
  const normal = f.ticker.getTicks();
  f.ticker.setFPS(15); f.run(120, 1);
  const slowTicks = f.ticker.getTicks() - normal;
  assert.ok(slowTicks >= 13 && slowTicks <= 18, 'game 15 FPS must produce ~15 ticks, got ' + slowTicks);
  assert.ok(Math.abs(f.ticker.framerate - 15) < 0.001);
  f.ticker.setFPS(60); const before = f.ticker.getTicks(); f.run(120, 1);
  assert.ok(f.ticker.getTicks() - before >= 118, 'ending hit stop restores high-refresh scheduling');
  assert.equal(f.ticker.timingMode, f.ticker.RAF);
});

test('high-refresh hit stop follows actual requested ticks across display refresh rates', () => {
  const results = [];
  for (const hz of [60, 90, 120, 144, 165]) for (const requested of [5, 15, 30, 45]) {
    const f = frame(); f.send('highRefresh', true); f.run(hz, 1);
    const before = f.ticker.getTicks(); f.ticker.setFPS(requested); f.run(hz, 1);
    const actual = f.ticker.getTicks() - before;
    assert.ok(Math.abs(actual - requested) <= 2, 'hz=' + hz + ' requested=' + requested + ' actual=' + actual);
    f.ticker.setFPS(60); const high = f.ticker.getTicks(); f.run(hz, 1);
    assert.ok(f.ticker.getTicks() - high >= hz - 2);
    assert.ok(f.raf.size <= 2); f.context.__yahagiFrameRateRuntime.dispose();
    results.push({hz, requested, actual});
  }
  console.log('High-refresh actual tick matrix: ' + JSON.stringify(results));
});

test('setFPS observation preserves receiver arguments return exceptions and later wrapper ownership', () => {
  const f = frame(); f.context.__yahagiFrameRateRuntime.dispose();
  const marker = {}, receiver = {}, error = new Error('game setter failed');
  const calls = [];
  const custom = function(...args) {calls.push({receiver:this,args}); if(args[0] === 13) throw error; f.originalSetFPS(args[0]); return marker;};
  f.ticker.setFPS = custom;
  const source = fs.readFileSync(path.join(__dirname, '../android/app/src/main/kotlin/app/yahagi/kancollebrowser/browser/GameFrameRateBridgeScript.kt'), 'utf8').split('"""')[1];
  vm.runInContext(source, f.context);
  assert.notEqual(f.ticker.setFPS, custom, 'observe public game rate writes including equal values');
  assert.equal(f.ticker.setFPS.call(receiver, 17, 'extra'), marker);
  assert.equal(calls[0].receiver, receiver); assert.deepEqual(calls[0].args, [17, 'extra']);
  assert.throws(() => f.ticker.setFPS(13), value => value === error);
  const ours = f.ticker.setFPS;
  const later = function() {return ours.apply(this, arguments);};
  f.ticker.setFPS = later; f.context.__yahagiFrameRateRuntime.dispose();
  assert.equal(f.ticker.setFPS, later, 'dispose must preserve later third-party ownership');
  assert.equal(f.ticker.setFPS(25), marker, 'a retained wrapper must still call the original setter');
  const fresh = frame(); fresh.context.__yahagiFrameRateRuntime.dispose();
  assert.equal(fresh.ticker.setFPS, fresh.originalSetFPS, 'restore an owned observer on dispose');
});

test('setFPS observation does not coerce an original argument a second time', () => {
  const f = frame(); let conversions = 0;
  const argument = {valueOf() {conversions++; if (conversions > 1) throw new Error('unexpected observer conversion'); return 15;}};
  assert.doesNotThrow(() => f.ticker.setFPS(argument));
  assert.equal(conversions, 1);
  pauseNative(f); resumeNative(f); f.run(120, 1);
  assert.ok(Math.abs(f.ticker.framerate - 15) < 0.001);
});

test('the resume observation window expires for an absent ticker without adding recurring probes', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); f.ticker.reset(); resumeNative(f); f.run(120, 31);
  f.listen(); lose(f); f.run(120, 4);
  assert.equal(f.ticker.getTicks(), 0, 'an expired resume epoch must not revive new work');
  assert.equal([...f.timers.values()].filter(timer => !timer.repeat).length, 0);
});

test('a paused game may unpause after the bounded resume window expires', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); f.ticker.paused = true; lose(f); resumeNative(f); f.run(120, 32);
  const before = f.ticker.getTicks(); assert.equal(f.ticker.paused, true);
  f.ticker.paused = false; f.run(120, 4);
  assert.ok(f.ticker.getTicks() > before, 'observed game unpause starts one fresh gated check');
});

test('retained callbacks after a long sleep keep stock first delta semantics and never burst ticks', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  const deltas = []; f.ticker.addEventListener('tick', event => deltas.push(event.delta));
  const initial = f.ticker._startTime;
  pauseNative(f); f.advance(120000); resumeNative(f);
  const before = f.ticker.getTicks(); f.run(120, 1 / 120);
  assert.ok(f.ticker.getTicks() - before <= 1);
  assert.ok(deltas[0] > 120000, 'do not silently rewrite game delta/timeline semantics');
  assert.equal(f.ticker._startTime, initial);
});

test('a tick listener microtask may pause and resume without losing its registration', async () => {
  const f = frame(); f.send('fps60', true);
  let calls = 0, pauseNext = true;
  const listener = () => {calls++; if (pauseNext) {pauseNext = false; Promise.resolve().then(() => {f.ticker.paused = true;});}};
  f.ticker.addEventListener('tick', listener); f.run(120, 1 / 120);
  await Promise.resolve(); assert.equal(f.ticker.paused, true);
  pauseNative(f); resumeNative(f); f.run(120, 2);
  assert.equal(f.ticker.paused, true);
  assert.ok(f.ticker._listeners.tick.includes(listener));
  f.ticker.paused = false; const before = calls; f.run(120, 1);
  assert.ok(calls > before); assert.ok(f.raf.size <= 2);
});

test('a game listener exception keeps stock scheduling and is never swallowed by recovery', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  const error = new Error('game listener failure'); let fail = true;
  const listener = () => {if (fail) {fail = false; throw error;}};
  f.ticker.addEventListener('tick', listener);
  assert.throws(() => f.run(120, 1), value => value === error);
  const before = f.ticker.getTicks(); f.run(120, 3);
  assert.ok(f.ticker.getTicks() > before);
  assert.ok(f.ticker._listeners.tick.includes(listener));
  assert.ok(f.raf.size <= 2);
});

test('ticker replacement during a resume epoch repairs only the new live ticker', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); lose(f); resumeNative(f);
  const old = f.ticker; old.reset();
  vm.runInContext(tickerSource, f.context);
  const current = f.context.createjs.Ticker;
  const listener = () => {}; current.setFPS(60); current.addEventListener('tick', listener);
  lose(f, current); f.run(120, 4);
  assert.ok(current.getTicks() > 0);
  assert.equal(old.getTicks(), 0, 'retired ticker cannot be resurrected');
  assert.ok(current._listeners.tick.includes(listener)); assert.ok(f.raf.size <= 2);
});

test('game timer-id replacement earns grace without a duplicate scheduler', () => {
  const f = frame(); f.send('fps60', true); f.run(120, 1);
  pauseNative(f); lose(f); resumeNative(f);
  f.run(120, 0.5);
  f.ticker._timerId = null; f.ticker._setupTick();
  const gameId = f.ticker._timerId;
  const before = f.ticker.getTicks(); f.run(120, 4);
  assert.ok(f.ticker.getTicks() > before);
  assert.equal(f.cancelled.raf.includes(gameId), false, 'a newly scheduled healthy game callback is not cancelled');
  assert.ok(f.raf.size <= 2);
});

function random(seed) {
  let state = seed >>> 0;
  return () => {state ^= state << 13; state ^= state >>> 17; state ^= state << 5; return state >>> 0;};
}

const seedBase = 0x20261021, seedCount = 256, actionsPerSeed = 256;
for (let seedOffset = 0; seedOffset < seedCount; seedOffset++) {
  const seed = (seedBase + seedOffset) >>> 0;
  test('lifecycle state machine invariants seed=0x' + seed.toString(16), () => {
    const pick = random(seed), f = frame();
    f.send('fps60', true); f.run(120, 1);
    const listener = () => {};
    f.ticker.addEventListener('tick', listener);
    let paused = false, nativeForeground = true, domVisible = true, pageActive = true;
    let target = 'fps60', disposed = false;
    const startTime = f.ticker._startTime, trace = [];
    for (let step = 0; step < actionsPerSeed; step++) {
      const action = pick() % 10;
      trace.push(action);
      if (action === 0) {nativeForeground = !nativeForeground; f.send(target, nativeForeground);}
      if (action === 1) {domVisible = !domVisible; f.visible(domVisible);}
      if (action === 2) {pageActive = !pageActive; if (pageActive) f.pageShow(true); else f.pageHide(true);}
      if (action === 3) {paused = !paused; f.ticker.paused = paused;}
      if (action === 4) {target = target === 'fps60' ? 'fps30' : 'fps60'; f.send(target, nativeForeground);}
      if (action === 5 && !nativeForeground) lose(f);
      if (action === 6) {f.send(target, nativeForeground); f.visible(domVisible);}
      if (action === 7 && step > actionsPerSeed - 5 && !disposed) {disposed = true; f.context.__yahagiFrameRateRuntime.dispose();}
      if (action === 8) f.advance(pick() % 30000);
      const seconds = (pick() % 21 + 1) / 120;
      const before = f.ticker.getTicks(), rate = f.ticker.framerate;
      f.run(120, seconds);
      try {
        assert.equal(f.ticker._startTime, startTime, 'no ticker reset');
        assert.equal(f.counts().reloads, 0, 'no game reload');
        assert.equal(f.ticker.paused, paused, 'game owns paused');
        assert.ok(f.ticker._listeners.tick.includes(listener), 'listener retained');
        assert.ok(f.raf.size <= 2, 'at most game and meter RAF');
        assert.ok(f.ticker.getTicks() - before <= Math.ceil(seconds * rate) + 1, 'no duplicate or catch-up tick burst');
        assert.ok([...f.timers.values()].filter(timer => !timer.repeat).length <= 2, 'bounded owned probe plus possible game timeout');
        if (!nativeForeground || !domVisible || !pageActive || disposed) {
          assert.equal([...f.timers.values()].filter(timer => !timer.repeat && timer.fn !== f.ticker._handleTimeout).length, 0, 'inactive documents own no recovery timers');
        }
      } catch (error) {error.message += '\nseed=0x' + seed.toString(16) + ' step=' + step + ' trace=' + trace.join(','); throw error;}
    }
    if (!disposed) {
      f.send('fps30', false); f.pageShow(true); f.visible(true); f.ticker.paused = false;
      f.send('fps60', true); const before = f.ticker.getTicks(); f.run(120, 4);
      assert.ok(f.ticker.getTicks() > before, 'seed=0x' + seed.toString(16) + ' terminal game continuation');
    }
    f.context.__yahagiFrameRateRuntime?.dispose();
  });
}

for (let offset = 0; offset < 64; offset++) {
  const seed = (0x5e7f0000 + offset) >>> 0;
  test('game rate ownership state machine seed=0x' + seed.toString(16), () => {
    const f = frame(), pick = random(seed); f.send('fps60', true); f.run(120, 1);
    let requested = 60, target = 'fps60';
    for (let step = 0; step < 64; step++) {
      const action = pick() % 4;
      if (action === 0) {requested = [0.5, 5, 15, 20, 30, 45, 60][pick() % 7]; f.ticker.setFPS(requested);}
      if (action === 1) {target = 'fps30'; f.send(target, false);}
      if (action === 2) {target = 'fps60'; f.send(target, true);}
      if (action === 3) {f.pageHide(true); f.pageShow(true);}
      f.run(120, 1.1);
      assert.ok(Math.abs(f.ticker.framerate - Math.min(requested, target === 'fps30' ? 30 : 60)) < 0.001,
        'seed=0x' + seed.toString(16) + ' step=' + step + ' requested=' + requested + ' target=' + target);
      assert.ok(f.raf.size <= 2); assert.equal(f.ticker.paused, false);
    }
    f.context.__yahagiFrameRateRuntime.dispose();
  });
}

console.log('Deterministic workload: lifecycle seeds=256 base=0x20261021 actions/seed=256 (65536); rate seeds=64 base=0x5e7f0000 actions/seed=64 (4096); edge scenarios=15 including 20 high-refresh matrix scenarios.');
