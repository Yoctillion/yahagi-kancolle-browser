const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const native = fs.readFileSync(path.join(__dirname, '../android/app/src/main/kotlin/app/yahagi/kancollebrowser/browser/GameFrameReloadBridge.kt'), 'utf8');
const source = native.match(/val source: String =\s*"""([\s\S]*?)"""\.trimIndent/)[1];

function page({loading = true, root = true, wrapper = false, crossOrigin = false, top = true, sourceUrl = 'https://example.invalid/game'} = {}) {
  const listeners = new Map();
  const observers = [];
  const messages = [];
  const timers = [];
  let exists = wrapper;
  let reloads = 0;
  let sourceWrites = 0;
  const game = {contentWindow: {location: {reload() {if(crossOrigin) throw new Error('cross-origin');reloads++;}}},
    getAttribute: () => sourceUrl, setAttribute: () => sourceWrites++};
  const document = {readyState: loading ? 'loading' : 'complete', documentElement: root ? {} : null,
    getElementById: () => exists ? game : null,
    addEventListener(name, callback) {listeners.set(name, callback);}};
  const window = {YahagiGameFrameReload: {postMessage(raw) {messages.push(JSON.parse(raw));}},
    frames: [], addEventListener(name, callback) {listeners.set(name, callback);}};
  window.top = top ? window : {};
  window.parent = top ? window : {};
  const context = vm.createContext({document, window, MutationObserver: class {
    constructor(callback) {this.callback=callback;observers.push(this);}
    observe(target, options) {this.options = options;this.target = target;}
    disconnect() {this.disconnected = true;}
  }, setTimeout(callback) {timers.push(callback);}});
  return {messages, observers, document, run() {vm.runInContext(source, context);},
    wrapper(value) {exists=value;}, root() {document.documentElement={};},
    emit(name, event) {listeners.get(name)?.(event);},
    flushTimers() {while(timers.length) timers.shift()();},
    child(frame) {window.frames.push(frame);}, parent: window.parent,
    documentId: () => window.__yahagiGameFrameReloadDocumentId,
    mutate() {observers.filter(o=>!o.disconnected).forEach(o=>o.callback([]));},
    send(data) {window.YahagiGameFrameReload.onmessage({data:JSON.stringify(data)});},
    availability() {return messages.filter(m=>m.kind==='target').at(-1)?.available;},
    reloads: () => reloads, sourceWrites: () => sourceWrites};
}

const early = page({wrapper:true});early.run();
assert.equal(early.availability(), true, 'Existing htmlWrap must be reported before DOMContentLoaded');
const missingRoot = page({root:false});missingRoot.run();
assert.equal(missingRoot.availability(), false);
assert.ok(missingRoot.observers.length > 0, 'Document-start must observe the document while no root exists');
missingRoot.root();missingRoot.wrapper(true);missingRoot.mutate();
assert.equal(missingRoot.availability(), true, 'A wrapper parsed after root creation must be discovered before DOMContentLoaded');
assert.ok(missingRoot.observers.some(o=>o.options?.attributeFilter?.includes('id')), 'Changing an existing element id must be observed');
missingRoot.wrapper(false);missingRoot.mutate();
assert.equal(missingRoot.availability(), false, 'Removing/renaming htmlWrap must revoke the target');
missingRoot.wrapper(true);missingRoot.emit('DOMContentLoaded');
assert.equal(missingRoot.availability(), true, 'DOMContentLoaded remains a fallback probe');

const late = page({loading:false});late.run();late.wrapper(true);
late.send({kind:'probe',requestId:'new-request'});
assert.ok(late.messages.some(m=>m.kind==='target'&&m.available&&m.requestId==='new-request'), 'Reload probe must re-read a target even before its mutation callback');
late.send({kind:'reload',requestId:'new-request'});
assert.equal(late.reloads(), 1);
late.emit('pagehide');late.wrapper(true);late.mutate();
late.send({kind:'probe',requestId:'old-document'});
late.send({kind:'reload',requestId:'old-document'});
assert.equal(late.availability(), false, 'Pagehide must revoke old target availability');
assert.equal(late.reloads(), 1, 'A stale document must not execute later requests');

const cross = page({wrapper:true,crossOrigin:true});cross.run();cross.send({kind:'reload',requestId:'cross'});
assert.equal(cross.sourceWrites(),1,'Cross-origin child must keep the src fallback');
assert.equal(cross.messages.at(-1).result,'reloaded');

const unloading = page({wrapper:true});unloading.run();unloading.emit('beforeunload');
assert.equal(unloading.availability(),false,'An unloading document must revoke its target immediately');
unloading.flushTimers();unloading.send({kind:'probe',requestId:'still-unloading'});
assert.equal(unloading.availability(),false,'An old document awaiting navigation must remain retired even before pagehide');
unloading.send({kind:'probe',requestId:'wrong-document',documentId:'stale-nonce'});
assert.equal(unloading.availability(),false,'A mismatched main-document nonce must never reactivate an old context');
unloading.send({kind:'probe',requestId:'canceled-navigation',documentId:unloading.documentId()});
assert.equal(unloading.availability(),true,'An explicit probe confirming the current main document must recover canceled beforeunload');
const departed = page({wrapper:true});departed.run();departed.emit('beforeunload');departed.emit('pagehide');departed.flushTimers();
departed.send({kind:'probe',requestId:'departed',documentId:departed.documentId()});
assert.equal(departed.availability(),false,'The cancel-unload fallback must never revive a hidden document');
departed.emit('pageshow');departed.send({kind:'probe',requestId:'restored'});
assert.equal(departed.availability(),true,'Restoring a bfcache document must re-enable probing');
const restoredEmpty = page({wrapper:true});restoredEmpty.run();restoredEmpty.emit('pagehide');restoredEmpty.wrapper(false);
const emptyCount = restoredEmpty.messages.filter(m=>m.kind==='target').length;
restoredEmpty.emit('pageshow');
assert.ok(restoredEmpty.messages.filter(m=>m.kind==='target').length > emptyCount,'A restored empty frame must announce availability so it can receive a later probe');
const child = page({top:false,wrapper:true});child.run();
assert.equal(child.messages.some(m=>m.kind==='document'),false,'Child document-start must not announce a new main document');
child.emit('message',{source:{},data:{kind:'yahagi-reload-probe',requestId:'stranger'}});
assert.equal(child.messages.some(m=>m.requestId==='stranger'),false,'Sibling/unrelated windows must not trigger probing');
child.emit('message',{source:child.parent,data:{kind:'yahagi-reload-probe',requestId:'parent'}});
assert.equal(child.messages.at(-1).requestId,'parent','Only the current parent can probe a child');
child.emit('beforeunload');child.emit('message',{source:child.parent,data:{kind:'yahagi-reload-probe',requestId:'resume-child',resume:true}});
assert.equal(child.availability(),true,'A verified parent probe must recover a current child after canceled beforeunload');
child.emit('pagehide');child.emit('message',{source:child.parent,data:{kind:'yahagi-reload-probe',requestId:'hidden-child',resume:true}});
assert.equal(child.availability(),false,'Parent routing must never reactivate a hidden child document');
const descendants = page();descendants.run();
const forwarded = [];
descendants.child({postMessage(data) {forwarded.push(data);}});
descendants.send({kind:'probe',requestId:'tree'});
descendants.send({kind:'probe',requestId:'tree'});
assert.equal(forwarded.length,1,'Duplicate probes through native and parent paths must traverse each document once');
const appeared = page();appeared.run();appeared.send({kind:'probe',requestId:'late-probe'});
appeared.wrapper(true);appeared.mutate();
assert.equal(appeared.messages.at(-1).requestId,'late-probe','A target appearing while a probe is pending must confirm that request');
const removed = page({wrapper:true});removed.run();removed.send({kind:'probe',requestId:'removed'});removed.wrapper(false);
removed.send({kind:'reload',requestId:'removed'});
assert.equal(removed.messages.at(-1).result,'html_wrap_not_found','A target removed after probe must return the precise missing-target result');
const blocked = page({wrapper:true,crossOrigin:true,sourceUrl:''});blocked.run();blocked.send({kind:'reload',requestId:'blocked'});
assert.equal(blocked.messages.at(-1).result,'blocked','A frame without a source cannot use the cross-origin fallback');
console.log('Early root-safe/id detection, probe coalescing, late target, parent routing, lifecycle recovery and src fallback passed');
