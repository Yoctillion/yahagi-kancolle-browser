const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const kotlin = fs.readFileSync(process.argv[2], 'utf8');
const source = kotlin.match(/val source: String\s*=\s*"""([\s\S]*?)"""/)[1];
const capture = fs.readFileSync(process.argv[3], 'utf8');
const config = {sessionId: 7, token: 'test-session', ships: {'607': {
  graph: {api_boko_n: [180, 180], api_boko_d: [20, 240], api_weda: [0, 0]},
  resourceIds: ['package:coordinates'],
}}};
const raw = 'svdata={"api_result":1,"api_data":{"api_mst_ship":[{"api_id":607,"api_name":"伊47"}],"api_mst_shipgraph":[{"api_id":607,"api_boko_n":[1,2],"api_boko_d":[3,4],"api_weda":[9,9],"api_sortno":88},{"api_id":1,"api_boko_n":[9,10]}],"other":[1,2,3]}}';
function env(options = {}) {
  const reports = [], network = [], messages = [];
  class Xhr {
    constructor() { this.readyState = 0; this.responseType = ''; this.status = 0; this.events = {}; }
    open(method, url, async = true) { this.method = method; this.url = url; this.async = async; this.readyState = 1; }
    addEventListener(type, listener) { (this.events[type] ||= []).push(listener); }
    send(body) {
      const path = new URL(this.url, 'https://w01y.kancolle-server.com/kcs2/').pathname;
      if (path === '/__yahagi_mods__/coordinates.json') {
        this._text = JSON.stringify(options.config || config); this.status = 200; this.readyState = 4; return;
      }
      if (path === '/__yahagi_mods__/coordinates-report') {
        reports.push(JSON.parse(new URL(this.url, 'https://w01y.kancolle-server.com/').searchParams.get('payload')));
        this._text = '{}'; this.status = 200; this.readyState = 4; return;
      }
      network.push({method: this.method, url: this.url, body});
      this._text = options.raw === undefined ? raw : options.raw;
      this._json = (() => { try { return JSON.parse(this._text.replace(/^svdata=/, '')); } catch (_) { return null; } })();
      this.responseURL = new URL(this.url, 'https://w01y.kancolle-server.com/').href;
      this.status = options.status || 200; this.readyState = 4;
      this.onreadystatechange?.();
      for (const listener of this.events.readystatechange || []) listener.call(this);
      this.onload?.();
      for (const listener of this.events.loadend || []) listener.call(this);
    }
    get responseText() { if (!['', 'text'].includes(this.responseType)) throw new Error('InvalidStateError'); return this._text || ''; }
    get response() { return this.responseType === 'json' ? this._json : this.responseText; }
  }
  const context = vm.createContext({URL, URLSearchParams, Response, Headers, Request, TextEncoder, XMLHttpRequest: Xhr,
    location: options.location || {href: 'https://w01y.kancolle-server.com/kcs2/index.php', protocol: 'https:', hostname: 'w01y.kancolle-server.com', port: ''},
    performance: {timeOrigin: 1}, setTimeout,
    fetch: async (url, init) => { network.push({url, init}); return new Response(options.raw === undefined ? raw : options.raw, {status: options.status || 200}); },
    YahagiNativeCapture: {postMessage: value => messages.push(JSON.parse(value))},
  });
  context.window = context;
  const injectMod = () => vm.runInContext(source, context);
  const injectCapture = () => vm.runInContext(capture.replaceAll('__YAHAGI_BINARY_CAPTURE_ENABLED__', 'false').replaceAll('__YAHAGI_CAPTURE_SESSION_ID__', 'capture-test'), context);
  if (options.captureFirst) injectCapture();
  injectMod();
  if (options.captureLast) injectCapture();
  return {context, reports, network, messages, injectMod};
}
function request(e, type = '', path = '/kcsapi/api_start2/getData') {
  const xhr = new e.context.XMLHttpRequest(); xhr.open('POST', path); xhr.responseType = type;
  let observed;
  xhr.onreadystatechange = () => { observed = type === 'json' ? xhr.response : xhr.responseText; };
  xhr.send('api_token=unchanged&api_verno=1');
  return {xhr, observed};
}
function parse(value) { return JSON.parse(typeof value === 'string' ? value.replace(/^svdata=/, '') : JSON.stringify(value)); }
function checkPatched(value) {
  const data = parse(value).api_data;
  assert.deepEqual(data.api_mst_shipgraph[0].api_boko_n, [180, 180]);
  assert.deepEqual(data.api_mst_shipgraph[0].api_boko_d, [20, 240]);
  assert.deepEqual(data.api_mst_shipgraph[0].api_weda, [0, 0]);
  assert.equal(data.api_mst_shipgraph[0].api_sortno, 88);
  assert.equal(data.api_mst_ship[0].api_name, '伊47');
  assert.deepEqual(data.api_mst_shipgraph[1].api_boko_n, [9, 10]);
  assert.deepEqual(data.other, [1, 2, 3]);
}
let assertions = 0;
async function run() {
  for (let round = 1; round <= 3; round++) {
    for (const type of ['', 'text', 'json']) {
      const e = env(); const {xhr, observed} = request(e, type);
      checkPatched(observed); checkPatched(xhr.response);
      assert.equal(e.reports.length, 1); assert.deepEqual(e.reports[0].resourceIds, ['package:coordinates']);
      assert.equal(e.network[0].body, 'api_token=unchanged&api_verno=1');
      assert.equal(e.network.length, 1);
      assertions++;
    }
    for (const order of ['captureFirst', 'captureLast']) {
      const e = env({[order]: true}); checkPatched(request(e).observed);
      assert.equal(e.messages[0].responseBody, raw);
      const response = await e.context.fetch('/kcsapi/api_start2/getData', {method: 'POST'});
      assert.ok(response instanceof Response); checkPatched(await response.text());
      await new Promise(setImmediate);
      assert.equal(e.messages.at(-1).responseBody, raw);
      assertions++;
      const jsonCapture = env({[order]: true}); checkPatched(request(jsonCapture, 'json').observed);
      assert.deepEqual(JSON.parse(jsonCapture.messages[0].responseBody), parse(raw));
      assertions++;
    }
    const e = env(); e.injectMod();
    assert.equal(request(e, '', '/kcsapi/api_port/port').observed, raw); assert.equal(e.reports.length, 0);
    checkPatched(request(e).observed); assert.equal(e.reports.length, 1); assertions++;
    const off = env({config: {sessionId: 8, token: 'off', ships: {}}});
    assert.equal(request(off).observed, raw); assert.equal(off.reports.length, 0); assertions++;
    for (const body of ['svdata={bad', '{"api_result":0}', '{"api_result":1,"api_data":{"api_mst_shipgraph":[]}}']) {
      const fail = env({raw: body}); assert.equal(request(fail).observed, body);
      assert.ok(fail.reports.some(r => r.failure === 'coordinate_apply_failed')); assertions++;
    }
    const failedHttp = env({status: 500}); assert.equal(request(failedHttp).observed, raw); assertions++;
    const reuse = env(); const {xhr} = request(reuse); xhr.open('POST', '/kcsapi/api_port/port'); xhr.send();
    assert.equal(xhr.responseText, raw); assertions++;
    const captureOnly = env({captureLast: true});
    const unopened = new captureOnly.context.XMLHttpRequest(); unopened.open('POST', '/kcsapi/api_start2/getData'); unopened.send();
    assert.equal(captureOnly.messages[0].responseBody, raw); assert.equal(captureOnly.reports.length, 0); assertions++;
    const plain = env({raw: raw.slice(7)}); checkPatched(request(plain).observed); assertions++;
    const missing = env({raw: '{"api_result":1,"api_data":{"api_mst_shipgraph":[{"api_id":1,"api_boko_n":[2,3]}]}}'});
    const missingData = parse(request(missing).observed); assert.deepEqual(missingData.api_data.api_mst_shipgraph[0].api_boko_n, [2,3]);
    assert.equal(missing.reports[0].failure, 'coordinate_apply_failed'); assertions++;
    const elsewhere = env({location: {href: 'https://example.test/', protocol: 'https:', hostname: 'example.test', port: ''}});
    assert.equal(request(elsewhere).observed, raw); assert.equal(elsewhere.reports.length, 0); assertions++;
    const external = env(); assert.equal(request(external, '', 'https://example.test/kcsapi/api_start2/getData').observed, raw);
    assert.equal(external.reports.length, 0); assertions++;
    const cloneEnv = env({raw: raw.slice(7)}); const cloneResponse = await cloneEnv.context.fetch('/kcsapi/api_start2/getData');
    checkPatched(await cloneResponse.clone().text()); checkPatched(await cloneResponse.json());
    assertions++;
  }
  console.log(`coordinate execution: ${assertions} scenarios passed (3 rounds; XHR text/json, fetch, capture both orders, off/failure/reuse)`);
}
run().catch(error => { console.error(error); process.exitCode = 1; });
