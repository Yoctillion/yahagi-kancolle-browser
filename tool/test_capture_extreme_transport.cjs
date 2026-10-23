const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('lib/src/bridge/native_game_capture_script.dart', 'utf8');
const match = source.match(/return '''\r?\n([\s\S]+?)\r?\n''';/);
assert.ok(match);
const paths = [
  '/kcsapi/api_port/port',
  '/kcsapi/api_req_map/start',
  '/kcsapi/api_req_map/next',
  '/kcsapi/api_req_sortie/battle',
];
const script = match[1]
  .replace('$encodedPaths', JSON.stringify(paths))
  .replace('__YAHAGI_BINARY_CAPTURE_ENABLED__', 'false');
const events = [];
const observations = [];
const concurrent = process.argv.includes('--concurrent');
let resolveFirst;
let responseNumber = 0;
const firstResponse = new Promise((resolve) => { resolveFirst = resolve; });
const context = {
  URL,
  URLSearchParams,
  Request,
  Response,
  TextEncoder,
  FormData,
  performance: { timeOrigin: 1000 },
  location: { href: 'https://example.test/kcs2/' },
  fetch: () => {
    responseNumber += 1;
    return responseNumber === 1
      ? firstResponse
      : Promise.resolve(new Response('svdata={"api_result":1,"api_data":{"api_no":2}}'));
  },
  YahagiNativeCapture: {
    postMessage(payload) {
      const event = JSON.parse(payload);
      events.push(event);
      observations.push(`capture:${event.path}`);
    },
  },
};
context.window = context;
vm.runInNewContext(script, context);

async function main() {
  const chunkCount = Number(process.argv[2] || 1000);
  assert.ok(Number.isInteger(chunkCount) && chunkCount > 0 && chunkCount <= 10000);
  const portPromise = context.fetch(paths[0], { method: 'POST', body: 'api_token=secret' });
  const body = `svdata={"api_result":1,"api_data":{"api_ship":[],"padding":"${'x'.repeat(chunkCount * 1024)}"}}`;
  let offset = 0;
  let delayedController;
  const bytes = new TextEncoder().encode(body);
  resolveFirst(new Response(new ReadableStream({
    pull(controller) {
      if (concurrent) {
        delayedController = controller;
        return;
      }
      if (offset === bytes.length) {
        controller.close();
        return;
      }
      controller.enqueue(bytes.slice(offset, offset + 1024));
      offset = Math.min(offset + 1024, bytes.length);
    },
  })));
  const port = await portPromise;
  if (!concurrent) {
    await port.text();
    observations.push('game:port-body-complete');
  }
  const map = await context.fetch(paths[1], { method: 'POST', body: 'api_deck_id=1' });
  await map.text();
  observations.push('game:map-body-complete');
  const deadline = Date.now() + 10000;
  if (concurrent) {
    while (events.length === 0 && Date.now() < deadline) await new Promise(setImmediate);
    assert.ok(events.length > 0, 'map capture timed out before releasing port');
    delayedController.enqueue(bytes);
    delayedController.close();
    await port.text();
    observations.push('game:port-body-complete');
  }
  while (events.length < 2 && Date.now() < deadline) {
    await new Promise(setImmediate);
  }
  assert.equal(events.length, 2);
  const publishedPaths = events.map((event) => event.path);
  assert.deepEqual(publishedPaths, concurrent ? [paths[1], paths[0]] : [paths[0], paths[1]]);
  process.stdout.write(`${JSON.stringify({ chunkCount, concurrent, observations, publishedPaths })}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack}\n`);
  process.exitCode = 1;
});
