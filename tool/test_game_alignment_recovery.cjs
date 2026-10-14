const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../lib/src/browser/game_page_alignment_script.dart'), 'utf8').split("r'''")[1].split("''';")[0];
function page(hostname = 'play.games.dmm.com', pathname = '/game/kancolle') {
  const elements = new Map();
  const messages = [];
  let observer;
  let observerCount = 0;
  let scans = 0;
  let writes = 0;
  let scrolls = 0;
  let visible = true;
  let dialogOpen = false;
  let canvasVisible = false;
  let ooiVisible = false;
  const scheduled = new Map();
  let nextTask = 0;
  const listeners = new Map();
  const on = (name, fn) => { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); };
  const off = (name, fn) => listeners.get(name)?.delete(fn);
  const properties = new Map();
  const element = () => ({isConnected: true, style: {removeProperty(name) {writes++;properties.delete(name);},
    setProperty(name, value) {writes++;properties.set(name, value);}, getPropertyValue: name => properties.get(name) || ''},
    getBoundingClientRect: () => ({width:1200,height:720}), setAttribute() {writes++;}, removeAttribute() {writes++;},
    remove() {writes++;}, contentWindow: {scrollTo() {scrolls++;}}});
  elements.set('game_frame', element());
  const canvas = {...element(), width: 1200, height: 720};
  const ooi = {...element(), querySelector: () => ooiVisible ? elements.get('game_frame') : null};
  elements.set('ooi-game', ooi);
  const context = {location: {hostname, pathname}, getComputedStyle: () => ({display:'block',visibility:'visible'}),
    document: {readyState:'complete', documentElement: {}, body:{},
      head: {appendChild(e) {writes++;elements.set(e.id,e);}}, createElement: element,
      addEventListener: on, removeEventListener: off,
      getElementById: id => elements.get(id), querySelector: () => ooiVisible ? elements.get('game_frame') : null,
      querySelectorAll: s => {scans++; return s === '#game_frame, #game-container' && visible ? [elements.get('game_frame')]
        : s === 'canvas' && canvasVisible ? [canvas] : s === 'dialog[open]' && dialogOpen ? [element()] : [];}},
    MutationObserver: class {constructor(cb) {observer=cb;observerCount++;} disconnect() {} observe() {}},
    setTimeout: cb => {const id = ++nextTask; scheduled.set(id, {kind:'timer',callback:cb}); return id;},
    clearTimeout: id => scheduled.delete(id),
    window: {scrollTo() {scrolls++;}, addEventListener: on, removeEventListener: off,
      requestAnimationFrame: cb => {const id = ++nextTask; scheduled.set(id, {kind:'frame',callback:cb}); return id;},
      cancelAnimationFrame: id => scheduled.delete(id),
      visualViewport: {width: 1200, height: 720, addEventListener: on},
      YahagiPresentation: {postMessage: m => messages.push(m)}}};
  vm.createContext(context);
  return {messages, listeners, loading: value => {context.document.readyState = value ? 'loading' : 'complete';},
    show: value => {visible = value;}, dialog: value => {dialogOpen = value;},
    canvas: value => {canvasVisible = value;}, ooi: value => {ooiVisible = value;},
    run: () => vm.runInContext(source, context), mutate: () => observer?.([]),
    emit: event => {for (const callback of [...(listeners.get(event) || [])]) callback();},
    flush: (kind) => {for (const id of [...scheduled.keys()]) {const task = scheduled.get(id); if(task && (!kind || task.kind === kind)) {scheduled.delete(id);task.callback();}}},
    emptyDocument: () => {context.document.documentElement = null;context.document.head = null;context.document.body = null;},
    readyDocument: () => {context.document.documentElement = {};context.document.head = {appendChild(e) {elements.set(e.id,e);}};context.document.body = {};},
    noAnimationFrame: () => {delete context.window.requestAnimationFrame;},
    viewport: (width, height) => {context.window.visualViewport.width = width;context.window.visualViewport.height = height;},
    read: () => context.window.__yahagiMobileReadPresentation?.(),
    effects: () => ({writes,scrolls,messages:messages.length,observers:observerCount,tasks:scheduled.size}),
    property: name => properties.get(name), observers: () => observerCount, scans: () => scans};
}
const game = page();
assert.equal(game.run(), 'game');
const before = game.messages.length;
assert.equal(game.run(), 'game');
assert.equal(game.messages.length, before + 1, 'Explicit fit must reach Android even when game state is unchanged');
assert.equal(game.messages.at(-1), 'game-fit');
const fitted = game.messages.length;
for (let i=0;i<10;i++) game.mutate();
game.flush();
assert.equal(game.messages.length, fitted, 'DOM mutations must not create a refit loop');
const login = page('accounts.dmm.com', '/login');
assert.equal(login.run(), 'web');
assert.equal(login.run(), 'web');
assert.deepEqual(login.messages, ['web'], 'Login pages must not request game scaling');
const delayed = page();
delayed.show(false);
assert.equal(delayed.run(), 'pending');
delayed.show(true);
delayed.mutate();
delayed.flush();
assert.equal(delayed.messages.at(-1), 'game', 'Late game frame must bind native scaling');
delayed.run();
assert.equal(delayed.messages.at(-1), 'game-fit', 'Page finish must force final sizing after early binding');
console.log('Alignment recovery: repeated fit, mutation deduplication, login isolation passed');
for (const [host, url] of [
  ['play.games.dmm.com', '/game/kancolle'],
  ['www.dmm.com', '/netgame/social/-/gadgets/=/app_id=854854/'],
  ['osapi.dmm.com', '/gadgets/ifr'],
]) {
  const loading = page(host, url);
  loading.loading(true);
  for (let cycle = 0; cycle < 200; cycle++) {
    loading.run();
    for (let mutation=0;mutation<10;mutation++) loading.mutate();
    loading.flush();
    assert.equal(loading.listeners.get('load')?.size, 1, 'Repeated fits during slow loading must not accumulate load listeners');
    assert.equal(loading.listeners.get('scroll')?.size, 1);
  }
  assert.equal(loading.messages.length, 200, 'Mutations must not amplify explicit fit requests');
  loading.loading(false);
  loading.show(false);
  loading.mutate();
  loading.flush();
  assert.equal(loading.messages.at(-1), 'pending');
  loading.show(true);
  loading.mutate();
  loading.flush();
  assert.equal(loading.messages.at(-1), 'game');
}
console.log('Slow-load stress: 600 explicit fits and 6000 DOM changes passed');

const once = page();
once.run();
for (let i = 0; i < 20; i++) once.run();
assert.equal(once.observers(), 1, 'Repeated sync must reuse the installed document observer');
const scanned = once.scans();
for (let i = 0; i < 100; i++) once.mutate();
assert.equal(once.scans(), scanned, 'Mutation callbacks must defer DOM scans');
once.flush('frame');
assert.ok(once.scans() - scanned <= 3, 'A mutation burst must perform at most one presentation scan');
const afterBurst = once.scans();
once.flush();
assert.equal(once.scans(), afterBurst, 'Fallback timer must not rescan after rAF completed');

const popup = page();
popup.run();
popup.dialog(true);popup.mutate();popup.flush();
assert.equal(popup.messages.at(-1), 'web', 'An open login/purchase dialog must release game locks');
popup.dialog(false);popup.mutate();popup.flush();
assert.equal(popup.messages.at(-1), 'game', 'Closing a dialog must restore the game presentation');

const standalone = page('w01.kancolle-server.com', '/kcs2/index.php');
standalone.show(false);standalone.run();
standalone.canvas(true);standalone.mutate();standalone.flush();
assert.equal(standalone.messages.at(-1), 'game', 'Late standalone canvas must remain supported');

const withoutRaf = page();
withoutRaf.noAnimationFrame();withoutRaf.show(false);withoutRaf.run();
withoutRaf.show(true);withoutRaf.mutate();withoutRaf.flush();
assert.equal(withoutRaf.messages.at(-1), 'game', 'A bounded timer must work without animation frames');
const pausedRaf = page();
pausedRaf.show(false);pausedRaf.run();pausedRaf.show(true);pausedRaf.mutate();pausedRaf.flush('timer');
assert.equal(pausedRaf.messages.at(-1),'game','The fallback must recover even when an installed rAF callback never runs');
const scansAfterTimer = pausedRaf.scans();pausedRaf.flush('frame');
assert.equal(pausedRaf.scans(),scansAfterTimer,'A delayed rAF must be canceled after the fallback timer');
const explicit = page();explicit.run();explicit.mutate();explicit.run();
const scansAfterExplicit = explicit.scans();explicit.flush();
assert.equal(explicit.scans(),scansAfterExplicit,'Explicit sync must consume any pending mutation scan');

const parsing = page();parsing.loading(true);parsing.emptyDocument();
assert.equal(parsing.run(),'pending','Document-start without root/head/body must safely remain pending');
parsing.readyDocument();parsing.mutate();parsing.flush();
assert.equal(parsing.messages.at(-1),'game','A parsed game document must recover after early installation');

const ooiGame = page('ooi.moe', '/kancolle');
ooiGame.show(false);ooiGame.run();ooiGame.ooi(true);ooiGame.mutate();ooiGame.flush();
assert.equal(ooiGame.property('--yahagi-ooi-scale'), '1', 'Late Ooi frame must be fitted');
ooiGame.viewport(600, 360);ooiGame.emit('resize');ooiGame.flush();
assert.equal(ooiGame.property('--yahagi-ooi-scale'), '0.5', 'Fold/resize must refit the Ooi surface');
console.log('Runtime reuse, bounded mutation scans, popup recovery, standalone canvas and Ooi resize passed');

const readOnly = page();readOnly.run();
const unchanged = readOnly.effects();
assert.equal(readOnly.read(),'game','Native presentation probing must read the current visible game');
readOnly.show(false);
assert.equal(readOnly.read(),'pending','Pure probes must inspect current DOM rather than a cached presentation state');
readOnly.dialog(true);
assert.equal(readOnly.read(),'web','Pure probes must recognize a blocking dialog');
readOnly.dialog(false);readOnly.canvas(true);
assert.equal(readOnly.read(),'game','Pure probes must support a standalone game canvas');
readOnly.emptyDocument();
assert.equal(readOnly.read(),'pending','Pure probes must tolerate a document that has not been parsed');
assert.deepEqual(readOnly.effects(),unchanged,'Pure probes must not fit, mutate, notify, schedule or install anything');
const loginBeforeRead = login.effects();
assert.equal(login.read(),'web');assert.deepEqual(login.effects(),loginBeforeRead);
const ooiBeforeRead = ooiGame.effects();
assert.equal(ooiGame.read(),'web');assert.deepEqual(ooiGame.effects(),ooiBeforeRead);
console.log('Pure current-document presentation reads have no fitting, mutation or notification side effects');
