#!/usr/bin/env node
// Real browser regression for shared/isolated website identity. Uses only Kelpie's supported API.
// Run against a disposable verification profile, then restart the app and run --phase restore.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { parseArgs } from 'node:util';

const { values } = parseArgs({ options: {
  readiness: { type: 'string' }, state: { type: 'string' },
  phase: { type: 'string', default: 'seed' }, port: { type: 'string', default: '18527' },
} });
assert(values.readiness && values.state, '--readiness and --state are required; use a disposable app profile');
const readiness = JSON.parse(await readFile(values.readiness, 'utf8'));
const endpoint = `http://127.0.0.1:${readiness.port}/v1/`;
const state = values.phase === 'restore' ? JSON.parse(await readFile(values.state, 'utf8')) : {
  prefix: `session-${randomUUID()}`, cookie: `kelpie_${randomUUID().replaceAll('-', '')}`,
};
const server = createServer((request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname.startsWith('/seed-')) {
    response.setHeader('Set-Cookie', `${state.cookie}=${url.pathname.slice(6)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600`);
  }
  response.setHeader('Content-Type', 'text/html');
  response.end('<title>Session storage fixture</title><h1>Session storage fixture</h1><a id="popup" href="/popup" target="_blank">Open another tab</a>');
});
await new Promise(resolve => server.listen(Number(values.port), '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${values.port}`;
async function call(method, body = {}) {
  const response = await fetch(endpoint + method, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${readiness.token}` },
    body: JSON.stringify(body), signal: AbortSignal.timeout(35000),
  });
  const result = await response.json();
  assert.equal(result.success, true, `${method}: ${result.error?.code ?? response.status} ${result.error?.message ?? ''}`);
  return result;
}
async function selected(tabId) {
  await call('switch-tab', { tabId });
  for (let attempt = 0; attempt < 100; attempt++) {
    const tabs = (await call('get-tabs')).tabs;
    const tab = tabs.find(item => item.id === tabId);
    if (tab && !tab.isLoading && tab.title === 'Session storage fixture') return;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('Fixture page did not finish loading');
}
async function cookie(tabId) {
  await selected(tabId);
  const cookies = (await call('get-cookies', { tabId, url: origin, name: state.cookie })).cookies;
  return cookies.find(item => item.name === state.cookie);
}
async function storage(tabId) {
  await selected(tabId);
  return (await call('get-storage', { tabId, type: 'local', key: state.cookie })).entries[state.cookie];
}
async function verify() {
  assert.equal((await cookie(state.normal)).value, 'shared');
  assert.equal((await cookie(state.normalSibling)).value, 'shared');
  assert.equal((await cookie(state.isolated)).value, 'isolated');
  assert.equal((await cookie(state.isolatedSibling)).value, 'isolated');
  assert.equal(await cookie(state.other), undefined);
  assert.equal(await storage(state.normalSibling), 'shared');
  assert.equal(await storage(state.isolatedSibling), 'isolated');
  assert.equal(await storage(state.other), undefined);
}
try {
  if (values.phase === 'seed') {
    async function tab(name, path, partition) {
      const result = await call('new-tab', { url: origin + path, name: `${state.prefix}-${name}`, ...(partition ? { partition } : {}) });
      await selected(result.tabId);
      assert.equal(result.tab.partition, partition);
      return result.tabId;
    }
    state.normal = await tab('normal', '/seed-shared');
    state.normalSibling = await tab('normal-sibling', '/probe');
    state.isolated = await tab('isolated', '/seed-isolated', state.prefix);
    state.isolatedSibling = await tab('isolated-sibling', '/probe', state.prefix);
    state.other = await tab('other', '/probe', `${state.prefix}-other`);
    await selected(state.normal);
    await call('set-storage', { tabId: state.normal, type: 'local', key: state.cookie, value: 'shared' });
    await selected(state.isolated);
    await call('set-storage', { tabId: state.isolated, type: 'local', key: state.cookie, value: 'isolated' });
    assert.equal((await cookie(state.normal)).httpOnly, true);
    await verify();
    const before = (await call('get-tabs')).tabs.map(item => item.id);
    await selected(state.isolated);
    await call('click', { tabId: state.isolated, selector: '#popup' });
    let popup;
    for (let attempt = 0; attempt < 30; attempt++) {
      popup = (await call('get-tabs')).tabs.find(item => !before.includes(item.id));
      if (popup) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert(popup, 'Desktop popup must become a browser tab');
    assert.equal(popup.partition, state.prefix);
    assert.equal((await cookie(popup.id)).value, 'isolated');
    await writeFile(values.state, JSON.stringify(state), { mode: 0o600 });
    console.log('PASS: ordinary siblings, isolated siblings, distinct partitions, HttpOnly cookies, localStorage and popup inheritance');
  } else {
    const tabs = (await call('get-tabs')).tabs;
    for (const key of ['normal', 'normalSibling', 'isolated', 'isolatedSibling', 'other']) {
      assert(tabs.some(tab => tab.id === state[key]), `Missing restored ${key} tab`);
      await call('navigate', { tabId: state[key], url: origin + '/probe' });
    }
    await verify();
    console.log('PASS: persistent default and isolated identities after app restart');
  }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
