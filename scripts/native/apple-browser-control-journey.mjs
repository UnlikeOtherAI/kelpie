#!/usr/bin/env node
import assert from 'node:assert/strict';
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { Client } from '../../packages/cli/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StreamableHTTPClientTransport } from '../../packages/cli/node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js';

// Run only against an explicitly launched local candidate. Pairing remains a
// visible native approval; its token is retained in this process and revoked.
const endpoint = new URL(process.argv[2] ?? 'http://127.0.0.1:18520');
assert.equal(endpoint.hostname, '127.0.0.1');
const platform = process.argv[3] ?? 'macos';
let token;
let replacement = 0;
const pendingCommands = new Set();
const fixture = http.createServer((req, res) => {
  if (req.url?.startsWith('/command?')) {
    res.setHeader('Content-Type', 'application/json');
    const after = Number(new URL(req.url, 'http://127.0.0.1').searchParams.get('after'));
    if (after !== replacement) res.end(JSON.stringify({ replacement }));
    else { pendingCommands.add(res); res.on('close', () => pendingCommands.delete(res)); }
    return;
  }
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(`<!doctype html><title>Browser control candidate fixture</title>
    <style>body{font:24px system-ui;padding:30px}button,input{font:24px system-ui;margin:12px}input{width:260px}</style>
    <h1>Browser control candidate fixture</h1><button id="activate">Activate</button>
    <p id="status">Not activated</p><form><label>Entry<input id="entry" name="entry" value="seed-"></label></form>
    <div contenteditable="true" aria-label="Editable">editable-secret</div>
    <textarea aria-label="Notes">textarea-secret</textarea><input type="password" value="password-secret" aria-label="Password">
    <a href="https://example.test/fixture">Fixture link</a><p id="replacement">Original</p>
    <script>

      document.querySelector('#activate').onclick = () => document.querySelector('#status').textContent = 'Activated';
      // A hostile page realm must not replace the private reader's intrinsics.
      window.WeakMap = class { get() { return 'spoofed'; } set() { throw new Error('page registry spoof'); } };
      Element.prototype.click = () => { document.querySelector('#status').textContent = 'Page-world spoof'; };
      // One pending request per navigation; no traffic-observer polling storm.
      fetch('/command?after=${replacement}').then(response => response.json()).then(() => {
        const old = document.querySelector('#activate');
        old.replaceWith(old.cloneNode(true));
        document.querySelector('#replacement').textContent = 'Replaced';
      });
    </script>`);
});
await new Promise(resolve => fixture.listen(18846, '127.0.0.1', resolve));
const fixtureURL = 'http://127.0.0.1:18846/';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function wire(path, body, method = 'POST', headers = {}) {
  const response = await fetch(new URL(path, endpoint), {
    signal: AbortSignal.timeout(40_000),
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    ...(method === 'POST' ? { body: JSON.stringify(body) } : {})
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
async function core(method, tabId, params = {}) {
  const response = await wire('/v1/browser-control', { version: 1, method, ...(tabId ? { tabId } : {}), params });
  assert.equal(response.status, 200);
  return response.body;
}
function assertCoreSuccess(response, operation) {
  const error = response.error;
  assert.equal(response.ok, true, `${operation}: ${JSON.stringify({
    code: error?.code, mayHaveCompleted: error?.mayHaveCompleted
  })}`);
}
async function native(method, params = {}) {
  const response = await wire(`/v1/${method}`, params);
  assert.equal(response.status, 200, `${method} HTTP refusal`);
  assert.equal(response.body.success, true, `${method} failed`);
  return response.body;
}
async function snapshot(tabId, predicate = () => true) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const response = await core('tab.snapshot', tabId, { maxChars: 3000, maxElements: 100 });
    if (response.ok && predicate(response.value)) return response.value;
    await pause(100);
  }
  throw new Error('Candidate fixture snapshot did not settle');
}
async function verifyRenderer(label, tabId) {
  assertCoreSuccess(await core('tab.goto', tabId, { url: fixtureURL }), `${label} tab.goto`);
  const observed = await snapshot(tabId, value => value.elements.some(el => el.name === 'Activate'));
  for (const secret of ['editable-secret', 'textarea-secret', 'password-secret']) assert(!JSON.stringify(observed).includes(secret));
  const button = observed.elements.find(el => el.name === 'Activate');
  assert(button?.ref);
  assertCoreSuccess(await core('tab.click', tabId, { ref: button.ref }), `${label} tab.click`);
  await snapshot(tabId, value => value.text.includes('Activated'));
  const fresh = await snapshot(tabId);
  const entry = fresh.elements.find(el => el.name === 'Entry');
  assert(entry?.ref);
  assertCoreSuccess(await core('tab.type', tabId, { ref: entry.ref, text: 'tail' }), `${label} tab.type`);
  const form = await native('get-form-state', { tabId, selector: 'form' });
  assert(JSON.stringify(form).includes('seed-tail'), 'Common type must append');
  const beforeReplacement = await snapshot(tabId);
  const oldButton = beforeReplacement.elements.find(el => el.name === 'Activate');
  replacement++;
  for (const response of pendingCommands) response.end(JSON.stringify({ replacement }));
  pendingCommands.clear();
  for (let attempt = 0; attempt < 100; attempt++) {
    const text = await native('get-page-text', { tabId });
    if (JSON.stringify(text).includes('Replaced')) break;
    await pause(100);
  }
  const stale = await core('tab.click', tabId, { ref: oldButton.ref });
  assert.equal(stale.ok, false);
  assert.equal(stale.error.code, 'STALE_REFERENCE');
  assert.equal(stale.error.mayHaveCompleted, false);
  console.log(`${label}: private snapshot, secret omission, atomic click, append and DOM replacement refusal passed`);
}
let client;
let ownedTab;
try {
  assert.equal((await wire('/v1/browser-control', {})).status, 401);
  assert.equal((await wire('/mcp', {})).status, 401);
  const pairing = await wire('/v1/pair', { clientId: randomUUID(), clientName: 'Apple browser candidate fixture' });
  assert.equal(pairing.status, 202);
  console.log(`Waiting for visible native one-session pairing approval on ${endpoint.origin}`);
  for (let attempt = 0; attempt < 180; attempt++) {
    const status = await wire(`/v1/pair/status?requestId=${encodeURIComponent(pairing.body.requestId)}`, undefined, 'GET');
    if (status.body?.token) { token = status.body.token; break; }
    await pause(1000);
  }
  assert(token, 'Native pairing approval did not arrive');
  assert.equal((await wire('/mcp', undefined, 'GET')).status, 405);
  assert.equal((await wire('/mcp', {}, 'POST', { 'MCP-Protocol-Version': 'unsupported' })).status, 400);
  assert.equal((await wire('/mcp', {}, 'POST', { Origin: 'https://example.test' })).status, 403);
  client = new Client({ name: 'apple-candidate-fixture', version: '1' });
  await client.connect(new StreamableHTTPClientTransport(new URL('/mcp', endpoint), {
    requestInit: { headers: { Authorization: `Bearer ${token}` } }
  }));
  const catalog = await client.listTools();
  assert.equal(catalog.tools.length, 4);
  const list = await client.callTool({ name: 'kelpie_browser_control', arguments: { request: { version: 1, method: 'tabs.list', params: {} } } });
  assert.equal(JSON.parse(list.content.find(item => item.type === 'text').text).ok, true);
  console.log('Standard MCP client initialize/notification/list/call and transport refusals passed');
  if (platform === 'macos') await native('set-renderer', { engine: 'webkit' });
  const created = await core('tabs.new', undefined, { url: fixtureURL });
  assert.equal(created.ok, true);
  ownedTab = created.value.id;
  assert(ownedTab);
  assert.equal((await core('tabs.select', ownedTab)).ok, true);
  await verifyRenderer(platform === 'macos' ? 'Mac WebKit' : 'iOS WebKit', ownedTab);
  const screenshot = await client.callTool({ name: 'kelpie_browser_control', arguments: {
    request: { version: 1, method: 'tab.screenshot', tabId: ownedTab, params: {} }
  } });
  const images = screenshot.content.filter(item => item.type === 'image');
  assert.equal(images.length, 1);
  assert(!screenshot.content.filter(item => item.type === 'text').some(item => item.text.includes(images[0].data)));
  await writeFile(new URL(`../../tmp/${platform}-candidate.png`, import.meta.url), Buffer.from(images[0].data, 'base64'));
  const richImage = await client.callTool({ name: 'kelpie_extension', arguments: {
    name: 'kelpie_screenshot', arguments: { tabId: ownedTab, format: 'jpeg', fullPage: true, resolution: 'viewport' }
  } });
  assert.equal(richImage.isError, false, 'Existing rich screenshot options remain callable');
  if (platform === 'macos') {
    const wk = await snapshot(ownedTab);
    const prior = wk.elements.find(el => el.name === 'Activate');
    await native('set-renderer', { engine: 'chromium' });
    await verifyRenderer('Mac Chromium', 'chromium');
    const capabilities = await core('capabilities');
    assert(!capabilities.value.methods.includes('tabs.new'));
    await native('set-renderer', { engine: 'webkit' });
    const changed = await core('tab.click', ownedTab, { ref: prior.ref });
    assert.equal(changed.ok, false);
    console.log('Renderer switch invalidates references and Chromium advertises its supported methods');
  }
  console.log('Apple candidate browser journey passed');
} finally {
  if (ownedTab && token) await core('tabs.close', ownedTab).catch(() => {});
  if (client) await client.close().catch(() => {});
  try {
    if (token) {
      assert.equal((await wire('/v1/pair', undefined, 'DELETE')).status, 200, 'Own session revocation must succeed');
      assert.equal((await wire('/v1/browser-control', { version: 1, method: 'tabs.list', params: {} })).status, 401, 'Revoked bearer must be refused');
      console.log('Disposable one-session pairing revoked; old bearer refused');
    }
  } finally {
    for (const response of pendingCommands) response.end();
    fixture.closeAllConnections();
    fixture.close();
  }
}
