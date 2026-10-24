const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../lib/src/browser/game_page_alignment_script.dart'), 'utf8').split("r'''")[1].split("''';")[0];
function page(hostname = 'play.games.dmm.com', pathname = '/game/kancolle', {wrapper = 'ooi-game', tag = 'iframe', id = 'externalswf'} = {}) {
  const elements = new Map();
  const messages = [];
  let observer;
  let observerCount = 0;
  let scans = 0;
  let writes = 0;
  let scrolls = 0;
  let frameScrolls = 0;
  let visible = true;
  let dialogOpen = false;
  let loginFormVisible = false;
  let canvasVisible = false;
  let ooiVisible = false;
  let ooiHidden = false;
  const metas = [];
  let observerOptions;
  let automaticMutations = false;
  const scheduled = new Map();
  let nextTask = 0;
  const listeners = new Map();
  const on = (name, fn) => { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); };
  const off = (name, fn) => listeners.get(name)?.delete(fn);
  const properties = new Map();
  const notifyAttribute = name => {
    if (automaticMutations && observerOptions?.attributeFilter.includes(name)) observer?.([]);
  };
  const element = (tagName = 'div') => {
    const attributes = new Map();
    let attributeWrites=0;
    return {tagName: tagName.toUpperCase(), isConnected: true, get attributeWrites() {return attributeWrites;}, style: {removeProperty(name) {writes++;properties.delete(name);},
    setProperty(name, value) {writes++;properties.set(name, value);}, getPropertyValue: name => properties.get(name) || ''},
    getBoundingClientRect: () => ({width:1200,height:720}),
    getAttribute: name => attributes.get(name) ?? null,
    setAttribute(name, value) {writes++;attributeWrites++;attributes.set(name, value);notifyAttribute(name);},
    removeAttribute(name) {writes++;attributeWrites++;attributes.delete(name);notifyAttribute(name);},
    remove() {writes++;this.isConnected=false;for(const [id,node] of elements)if(node===this)elements.delete(id);}, contentWindow: {scrollTo() {scrolls++;}}};
  };
  const append = e => {writes++;e.isConnected=true;if(e.tagName==='META') metas.push(e);else elements.set(e.id,e);};
  elements.set('game_frame', element());
  const canvas = {...element(), width: 1200, height: 720};
  const ooiFrame = element();
  const matchesOoiFrame = selector => selector.split(',').some(part =>
    part.trim() === `${tag}#${id}` ||
    part.trim() === `${wrapper === 'ooi-game' ? '#ooi-page #ooi-game' : '#flashWrap'} > ${tag}#${id}`);
  const ooi = {...element(), querySelector: selector => ooiVisible && matchesOoiFrame(selector) ? ooiFrame : null};
  elements.set(wrapper, ooi);
  ooiFrame.parentElement = ooi;
  const frameWindow = {frameElement: ooiFrame, scrollTo() {frameScrolls++;}};
  ooiFrame.contentWindow = tag === 'iframe' ? frameWindow : undefined;
  const context = {location: {hostname, pathname}, getComputedStyle: element => ({display:element === ooiFrame && ooiHidden ? 'none' : 'block',visibility:'visible'}),
    document: {readyState:'complete', documentElement: {}, body:{},
      head: {appendChild:append}, createElement: element,
      addEventListener: on, removeEventListener: off,
      getElementById: id => elements.get(id), querySelector: selector => ooiVisible && matchesOoiFrame(selector) ? ooiFrame : null,
      querySelectorAll: s => {scans++; return s === 'meta[name]' ? metas.filter(e=>e.isConnected&&e.getAttribute('name')!==null)
        : s === '#game_frame, #game-container' && visible ? [elements.get('game_frame')]
        : s === 'canvas' && canvasVisible ? [canvas] : s === 'dialog[open]' && dialogOpen ? [element()]
        : s === 'input[type="password"], input[name="password"], input[autocomplete="current-password"], input[autocomplete="new-password"]' && loginFormVisible ? [element()]
        : ooiVisible && matchesOoiFrame(s) ? [ooiFrame] : [];}},
    MutationObserver: class {constructor(cb) {observer=cb;observerCount++;} disconnect() {} observe(_target,options) {observerOptions=options;}},
    setTimeout: cb => {const id = ++nextTask; scheduled.set(id, {kind:'timer',callback:cb}); return id;},
    clearTimeout: id => scheduled.delete(id),
    window: {scrollTo() {scrolls++;}, addEventListener: on, removeEventListener: off,
      frames: [frameWindow],
      requestAnimationFrame: cb => {const id = ++nextTask; scheduled.set(id, {kind:'frame',callback:cb}); return id;},
      cancelAnimationFrame: id => scheduled.delete(id),
      visualViewport: {width: 1200, height: 720, addEventListener: on},
      YahagiPresentation: {postMessage: m => messages.push(m)}}};
  vm.createContext(context);
  return {messages, listeners, loading: value => {context.document.readyState = value ? 'loading' : 'complete';},
    show: value => {visible = value;}, dialog: value => {dialogOpen = value;},
    loginForm: value => {loginFormVisible = value;},
    canvas: value => {canvasVisible = value;}, ooi: value => {ooiVisible = value;},
    hideOoi: value => {ooiHidden = value;}, hasStyle: id => elements.has(id),
    legacyOoiRuntime: () => {
      context.window.__yahagiMobilePresentationRuntimeVersion = 3;
      context.window.__yahagiMobileSyncPresentation = () => 'web';
      context.window.__yahagiMobileReadPresentation = () => 'web';
      context.window.__yahagiMobileOoiAlignGame = () => {};
      context.window.__yahagiMobileAlignGame = context.window.__yahagiMobileOoiAlignGame;
    },
    emptyOoiContainer: () => elements.set('ooi-game', {...element(), querySelector: () => null}),
    addMeta: (content, name = 'viewport') => {const meta=element('meta');meta.setAttribute('name',name);if(content!==null)meta.setAttribute('content',content);metas.push(meta);return meta;},
    metas: () => metas.filter(meta=>meta.isConnected),
    observeOwnMutations: () => {automaticMutations=true;},
    observerAttributes: () => observerOptions?.attributeFilter,
    oldViewportRuntime: restore => {context.window.__yahagiMobilePresentationRuntimeVersion=4;context.window.__yahagiMobileRestoreGameViewport=restore;},
    run: () => vm.runInContext(source, context), mutate: () => observer?.([]),
    emit: event => {for (const callback of [...(listeners.get(event) || [])]) callback();},
    flush: (kind) => {for (const id of [...scheduled.keys()]) {const task = scheduled.get(id); if(task && (!kind || task.kind === kind)) {scheduled.delete(id);task.callback();}}},
    emptyDocument: () => {context.document.documentElement = null;context.document.head = null;context.document.body = null;},
    readyDocument: () => {context.document.documentElement = {};context.document.head = {appendChild:append};context.document.body = {};},
    noAnimationFrame: () => {delete context.window.requestAnimationFrame;},
    viewport: (width, height) => {context.window.visualViewport.width = width;context.window.visualViewport.height = height;},
    read: () => context.window.__yahagiMobileReadPresentation?.(),
    effects: () => ({writes,scrolls,messages:messages.length,observers:observerCount,tasks:scheduled.size}),
    property: name => properties.get(name), observers: () => observerCount, scans: () => scans,
    frameScrolls: () => frameScrolls,
    frameAttribute: name => ooiFrame.getAttribute(name),
    setFrameAttribute: (name, value) => ooiFrame.setAttribute(name, value)};
}

// Entry/exit regressions: use the actual production runtime and its owned DOM state.
for (const tag of ['iframe', 'embed']) {
  const lifecycle = page('ooi.moe', '/poi', {wrapper:'flashWrap', tag});
  lifecycle.show(false);
  const original = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
  const viewport = lifecycle.addMeta(original);
  assert.equal(lifecycle.run(), 'pending', 'An initial OOI loading page remains pending');
  assert.equal(lifecycle.hasStyle('__yahagi_mobile_fixed_canvas__'), false);
  lifecycle.ooi(true); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'game');
  assert.match(viewport.getAttribute('content'), /minimum-scale=0\.01/);
  lifecycle.ooi(false); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'web', 'An active OOI surface removal must release native fitting');
  assert.equal(lifecycle.messages.at(-1), 'web');
  assert.equal(lifecycle.hasStyle('__yahagi_mobile_fixed_canvas__'), false, 'Exit removes game CSS');
  assert.equal(lifecycle.hasStyle('__yahagi_mobile_ooi_browser__'), false);
  assert.equal(lifecycle.listeners.get('scroll')?.size || 0, 0, 'Exit removes the scroll lock');
  assert.equal(viewport.getAttribute('content'), original, 'Exit restores original viewport exactly');
  lifecycle.ooi(true); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'game', 'A replacement OOI surface can acquire a fresh fit');
  lifecycle.dialog(true); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'web', 'A blocking dialog takes priority over an OOI surface');
  assert.equal(viewport.getAttribute('content'), original);
  lifecycle.dialog(false); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'game');
  lifecycle.loginForm(true); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'web', 'A visible OOI login form takes priority over a retained game frame');
  assert.equal(viewport.getAttribute('content'), original);
  lifecycle.loginForm(false); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'game');
  lifecycle.hideOoi(true); lifecycle.mutate(); lifecycle.flush();
  assert.equal(lifecycle.read(), 'web', 'An active hidden OOI surface must release fitting');
}
const hiddenOoi = page('ooi.moe', '/poi', {wrapper:'flashWrap'});
hiddenOoi.show(false); hiddenOoi.ooi(true); hiddenOoi.hideOoi(true);
assert.equal(hiddenOoi.run(), 'pending', 'A hidden frame cannot seize an initial login/loading page');
assert.equal(hiddenOoi.hasStyle('__yahagi_mobile_fixed_canvas__'), false);
for (const wrapper of ['ooi-game', 'flashWrap']) {
  const htmlWrap = page('ooi.moe', '/poi', {wrapper, id:'htmlWrap'});
  htmlWrap.show(false); htmlWrap.ooi(true);
  assert.equal(htmlWrap.run(), 'game', 'Visible htmlWrap uses native fit');
}
console.log('OOI native entry, dialog priority, hidden-frame isolation, exact viewport/scroll release and htmlWrap passed');

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
assert.equal(ooiGame.read(), 'game', 'Late Ooi frame must request native game fitting');
ooiGame.viewport(600, 360);ooiGame.emit('resize');ooiGame.flush();
assert.equal(ooiGame.read(), 'game', 'Fold/resize keeps native game presentation');
assert.equal(ooiGame.property('--yahagi-ooi-scale'), undefined, 'OOI must not layer CSS scaling over native scaling');
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
assert.equal(ooiGame.read(),'game');assert.deepEqual(ooiGame.effects(),ooiBeforeRead);
console.log('Pure current-document presentation reads have no fitting, mutation or notification side effects');

for (const [route, wrapper] of [
  ['/kancolle', 'ooi-game'], ['/kancolle/', 'ooi-game'],
  ['/poi', 'flashWrap'], ['/poi/', 'flashWrap'],
  ['/flash', 'flashWrap'], ['/flash/', 'flashWrap'],
]) {
  for (const tag of ['iframe', 'embed']) {
    const ooiMode = page('ooi.moe', route, {wrapper, tag});
    ooiMode.show(false);ooiMode.run();
    ooiMode.viewport(600, 360);ooiMode.ooi(true);ooiMode.mutate();ooiMode.flush();
    assert.equal(ooiMode.read(), 'game', `${route} ${tag} must fit a late game surface`);
    assert.equal(ooiMode.messages.at(-1), 'game', 'OOI wrappers request the shared native fit');
    const messagesBeforeResize = ooiMode.messages.length;
    ooiMode.viewport(1500, 900);ooiMode.emit('resize');ooiMode.flush();
    assert.equal(ooiMode.read(), 'game', `${route} ${tag} remains game after resize`);
    assert.equal(ooiMode.messages.length, messagesBeforeResize, 'Native layout fitting must not be amplified by JS resize notifications');
    const beforeRepair = ooiMode.frameScrolls();
    ooiMode.run();
    assert.ok(ooiMode.frameScrolls() > beforeRepair, `${route} ${tag} manual fit must reset a same-origin child scroll offset`);
  }
}

for (const route of ['/kancolle', '/poi', '/flash', '/kcs2/index.php']) {
  const directOoi = page('ooi.moe', route);
  directOoi.show(false);directOoi.run();
  directOoi.canvas(true);directOoi.mutate();directOoi.flush();
  assert.equal(directOoi.messages.at(-1), 'game', `${route} must fit a late standalone game canvas`);
  directOoi.dialog(true);directOoi.mutate();directOoi.flush();
  assert.equal(directOoi.messages.at(-1), 'web', 'An OOI dialog must release native game scaling');
}

for (const [host, route] of [['ooi.moe', '/'], ['ooi.moe', '/login'], ['ooi.moe', '/connector'], ['ooi.moe', '/poi-help'], ['ooi.moe.example.com', '/poi']]) {
  const otherOoi = page(host, route, {wrapper: 'flashWrap'});
  otherOoi.ooi(true);otherOoi.canvas(true);otherOoi.setFrameAttribute('scrolling', 'auto');
  assert.equal(otherOoi.run(), 'web', 'Only exact OOI game routes may be fitted');
  assert.equal(otherOoi.property('--yahagi-ooi-scale'), undefined);
  assert.equal(otherOoi.frameAttribute('scrolling'), 'auto', 'Excluded pages must preserve their own frame settings');
}
console.log('OOI browser/poi/flash routes, iframe/embed surfaces, standalone canvas, tablet resize and login isolation passed');

const twoOoiContainers = page('ooi.moe', '/poi', {wrapper: 'flashWrap'});
twoOoiContainers.emptyOoiContainer();twoOoiContainers.show(false);twoOoiContainers.ooi(true);twoOoiContainers.viewport(600, 360);
twoOoiContainers.run();
assert.equal(twoOoiContainers.read(), 'game', 'The visible detected game frame must select native fitting');

const releasedOoiFrame = page('ooi.moe', '/poi', {wrapper: 'flashWrap'});
releasedOoiFrame.show(false);releasedOoiFrame.ooi(true);releasedOoiFrame.setFrameAttribute('scrolling', 'auto');
releasedOoiFrame.run();
assert.equal(releasedOoiFrame.frameAttribute('scrolling'), 'no');
releasedOoiFrame.ooi(false);releasedOoiFrame.run();
assert.equal(releasedOoiFrame.frameAttribute('scrolling'), 'auto', 'Leaving an OOI surface must restore the original frame setting even after its selector changes');

const upgradedOoi = page('ooi.moe', '/poi', {wrapper: 'flashWrap', tag: 'embed'});
upgradedOoi.show(false);upgradedOoi.ooi(true);upgradedOoi.viewport(600, 360);upgradedOoi.legacyOoiRuntime();
upgradedOoi.run();
assert.equal(upgradedOoi.read(), 'game', 'A retained document must replace an older cached OOI alignment hook');
assert.ok(upgradedOoi.frameScrolls() > 0, 'Runtime upgrade must use the new same-origin embed scroll repair');

const viewportGame = page();
const originalViewport = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
const primaryViewport = viewportGame.addMeta(originalViewport);
const secondaryViewport = viewportGame.addMeta('WIDTH=1200; MINIMUM-SCALE=1; maximum-scale=2', 'VIEWPORT');
const unrelatedMeta = viewportGame.addMeta('Keep this value', 'description');
viewportGame.observeOwnMutations();
viewportGame.run();
for (const meta of [primaryViewport,secondaryViewport]) {
  assert.match(meta.getAttribute('content'),/minimum-scale=0\.01/,'Game scaling must release the WebView minimum zoom constraint');
  assert.match(meta.getAttribute('content'),/maximum-scale=10/);
  assert.match(meta.getAttribute('content'),/user-scalable=yes/);
  assert.equal((meta.getAttribute('content').match(/maximum-scale=/gi)||[]).length,1,'Old viewport zoom bounds must be replaced');
}
assert.match(primaryViewport.getAttribute('content'),/width=device-width/);
assert.match(primaryViewport.getAttribute('content'),/initial-scale=1/);
assert.match(primaryViewport.getAttribute('content'),/viewport-fit=cover/);
assert.match(secondaryViewport.getAttribute('content'),/WIDTH=1200/);
assert.equal(unrelatedMeta.getAttribute('content'),'Keep this value');
assert.ok(viewportGame.observerAttributes().includes('content'));
assert.ok(viewportGame.observerAttributes().includes('name'));
const metaWrites = [primaryViewport.attributeWrites,secondaryViewport.attributeWrites];
for(let repeat=0;repeat<20;repeat++) {viewportGame.run();viewportGame.emit('resize');viewportGame.flush();}
assert.deepEqual([primaryViewport.attributeWrites,secondaryViewport.attributeWrites],metaWrites,'Resize/reinjection must not rewrite an already owned viewport');
viewportGame.flush();
assert.equal(viewportGame.effects().tasks,0,'Own viewport mutations must settle without a resynchronization loop');
viewportGame.dialog(true);viewportGame.mutate();viewportGame.flush();
assert.equal(primaryViewport.getAttribute('content'),originalViewport,'Dialog cleanup must restore the first original snapshot');
assert.equal(secondaryViewport.getAttribute('content'),'WIDTH=1200; MINIMUM-SCALE=1; maximum-scale=2');
viewportGame.dialog(false);viewportGame.mutate();viewportGame.flush();
primaryViewport.setAttribute('content','width=1200, minimum-scale=2');
viewportGame.flush();
assert.match(primaryViewport.getAttribute('content'),/minimum-scale=0\.01/,'External viewport changes must restore game zoom bounds');
viewportGame.dialog(true);viewportGame.mutate();viewportGame.flush();
assert.equal(primaryViewport.getAttribute('content'),originalViewport,'An external update must not overwrite the entry snapshot');

const generatedViewportPage = page();
generatedViewportPage.run();
assert.equal(generatedViewportPage.metas().length,1,'Create exactly one viewport when the document has none');
generatedViewportPage.run();
assert.equal(generatedViewportPage.metas().length,1,'Explicit fit must reuse the created viewport');
generatedViewportPage.dialog(true);generatedViewportPage.run();
assert.equal(generatedViewportPage.metas().length,0,'Leaving the game must remove an app-created viewport');

const missingContentPage = page();
const missingContentMeta = missingContentPage.addMeta(null);
missingContentPage.run();
assert.match(missingContentMeta.getAttribute('content'),/minimum-scale=0\.01/);
missingContentPage.dialog(true);missingContentPage.run();
assert.equal(missingContentMeta.getAttribute('content'),null,'Cleanup must preserve a missing content attribute');
assert.equal(missingContentMeta.isConnected,true,'The original empty meta must remain in the document');

const renamedMetaPage = page();
const renamedMeta = renamedMetaPage.addMeta('width=1200, maximum-scale=1','description');
renamedMetaPage.observeOwnMutations();renamedMetaPage.run();
renamedMeta.setAttribute('name','viewport');renamedMetaPage.flush();
assert.match(renamedMeta.getAttribute('content'),/minimum-scale=0\.01/,'A renamed viewport must be discovered through attribute changes');
renamedMetaPage.dialog(true);renamedMetaPage.run();
assert.equal(renamedMeta.getAttribute('content'),'width=1200, maximum-scale=1');
assert.equal(renamedMetaPage.metas().length,1,'Cleanup must preserve the page meta and remove only the generated viewport');

const removedViewportPage = page();
const removedViewport = removedViewportPage.addMeta(originalViewport);
removedViewportPage.run();removedViewport.remove();
removedViewportPage.dialog(true);removedViewportPage.run();
assert.equal(removedViewport.isConnected,false,'Cleanup must not reattach a page-removed viewport');

const viewportOoi = page('ooi.moe','/poi');
const ooiViewport = viewportOoi.addMeta('width=device-width, user-scalable=no');
viewportOoi.show(false);viewportOoi.canvas(true);viewportOoi.run();
assert.match(ooiViewport.getAttribute('content'),/minimum-scale=0\.01/);
viewportOoi.ooi(true);viewportOoi.mutate();viewportOoi.flush();
assert.match(ooiViewport.getAttribute('content'),/minimum-scale=0\.01/,'OOI wrapper takeover keeps the native game viewport');
const viewportLogin = page('accounts.dmm.com','/login');
const loginViewport = viewportLogin.addMeta('width=device-width, maximum-scale=1');
viewportLogin.run();
assert.equal(loginViewport.getAttribute('content'),'width=device-width, maximum-scale=1','Accounts must retain their own viewport');

const upgradedViewportPage = page();
const upgradedViewportMeta = upgradedViewportPage.addMeta('minimum-scale=0.01, maximum-scale=10');
let oldViewportRestores=0;
upgradedViewportPage.oldViewportRuntime(() => {oldViewportRestores++;upgradedViewportMeta.setAttribute('content',originalViewport);});
upgradedViewportPage.run();
assert.equal(oldViewportRestores,1,'A runtime upgrade must release the previous viewport ownership hook');
upgradedViewportPage.dialog(true);upgradedViewportPage.run();
assert.equal(upgradedViewportMeta.getAttribute('content'),originalViewport,'Upgrade cleanup must retain the pre-takeover viewport');
console.log('Game viewport ownership, multiple/missing metadata, idempotent resize, runtime upgrade and web/OOI cleanup passed');
