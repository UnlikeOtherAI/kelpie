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
  mobile: { type: 'boolean', default: false },
  android: { type: 'boolean', default: false },
  'manual-popup': { type: 'boolean', default: false },
} });
const mobile = values.mobile || values.android;
assert(values.readiness && values.state, '--readiness and --state are required; use a disposable app profile');
const readiness = JSON.parse(await readFile(values.readiness, 'utf8'));
const endpoint = `http://127.0.0.1:${readiness.port}/v1/`;
const state = values.phase !== 'seed' ? JSON.parse(await readFile(values.state, 'utf8')) : {
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
async function call(method, body = {}, expectedError) {
  const response = await fetch(endpoint + method, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${readiness.token}` },
    body: JSON.stringify(body), signal: AbortSignal.timeout(35000),
  });
  const bodyText = await response.text();
  assert(bodyText.length > 0, `${method}: empty HTTP ${response.status} response`);
  const result = JSON.parse(bodyText);
  if (expectedError) assert.equal(result.error?.code, expectedError, `${method}: expected ${expectedError}`);
  else assert.equal(result.success, true, `${method}: ${result.error?.code ?? response.status} ${result.error?.message ?? ''}`);
  return result;
}
async function retire(id) {
  const before = new Set((await call('get-partitions')).partitions.map(item => item.id));
  await call('delete-partition', { id }, values.android ? 'PARTITION_IN_USE' : undefined);
  const after = (await call('get-partitions')).partitions.map(item => item.id);
  assert(!after.includes(id), 'A retired public name must no longer reference its old store');
  if (values.android) {
    const pending = after.filter(item => item.startsWith('orphan:') && !before.has(item));
    assert.equal(pending.length, 1, 'Android must expose its durable pending deletion');
    state.pending = [...(state.pending ?? []), ...pending];
  }
}
async function selected(tabId) {
  await call('switch-tab', { tabId });
  const deadline = Date.now() + 60000;
  while (Date.now() < deadline) {
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
  assert([undefined, null, ''].includes(await storage(state.other)), 'A separate partition must not inherit localStorage');
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
    const sharedCookie = await cookie(state.normal);
    // Android's native CookieManager exposes values but not cookie attributes.
    if (!values.android) assert.equal(sharedCookie.httpOnly, true);
    assert.equal((await call('evaluate', {
      tabId: state.normal, expression: `document.cookie.includes(${JSON.stringify(state.cookie)})`,
    })).result, false, 'The server-set HttpOnly cookie must be hidden from page scripts');
    await verify();
    const before = (await call('get-tabs')).tabs.map(item => item.id);
    state.names = Object.fromEntries((await call('get-tabs')).tabs.map(tab => [tab.id, tab.name]));
    await writeFile(values.state, JSON.stringify(state), { mode: 0o600 });
    await selected(state.isolated);
    if (values['manual-popup']) console.log('Click “Open another tab” in the active native fixture page.');
    else await call('click', { tabId: state.isolated, selector: '#popup' });
    if (mobile) {
      // Mobile opens target=_blank in its existing view; identity must remain intact.
      const deadline = Date.now() + (values['manual-popup'] ? 60000 : 15000);
      while ((await call('get-tabs')).tabs.find(tab => tab.id === state.isolated)?.url !== origin + '/popup') {
        assert(Date.now() < deadline, 'Mobile popup must navigate its opener');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      await selected(state.isolated);
      assert.equal((await cookie(state.isolated)).value, 'isolated');
      assert.equal((await call('get-tabs')).tabs.length, before.length);
    } else {
      let popup;
      for (let attempt = 0; attempt < 30; attempt++) {
        popup = (await call('get-tabs')).tabs.find(item => !before.includes(item.id));
        if (popup) break;
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      assert(popup, 'Desktop popup must become a browser tab');
      assert.equal(popup.partition, state.prefix);
      assert.equal((await cookie(popup.id)).value, 'isolated');
    }
    state.names = Object.fromEntries((await call('get-tabs')).tabs.map(tab => [tab.id, tab.name]));
    await writeFile(values.state, JSON.stringify(state), { mode: 0o600 });
    console.log('PASS: ordinary siblings, isolated siblings, distinct partitions, HttpOnly cookies, localStorage and popup inheritance');
  } else if (values.phase === 'cleanup') {
    for (const id of [state.prefix, `${state.prefix}-other`]) {
      await retire(id);
      assert(!(await call('get-tabs')).tabs.some(tab => tab.partition === id));
    }
    const normal = (await call('get-tabs')).tabs.find(tab => tab.name === state.names[state.normal]);
    assert(normal, 'Deleting a partition must keep ordinary tabs');
    assert.equal((await cookie(normal.id)).value, 'shared');
    const fresh = await call('new-tab', { url: origin + '/probe', partition: state.prefix });
    assert.equal(await cookie(fresh.tabId), undefined);
    await retire(state.prefix);
    await writeFile(values.state, JSON.stringify(state), { mode: 0o600 });
    console.log('PASS: partition deletion closes its tabs, preserves shared identity and recreates an empty store');
  } else if (values.phase === 'purged') {
    assert(values.android && state.pending?.length, 'Run Android cleanup before checking startup purge');
    const ids = (await call('get-partitions')).partitions.map(item => item.id);
    assert(state.pending.every(id => !ids.includes(id)), 'Startup must purge every retired fixture profile');
    console.log('PASS: Android startup purged every retired fixture profile');
  } else {
    const tabs = (await call('get-tabs')).tabs;
    for (const key of ['normal', 'normalSibling', 'isolated', 'isolatedSibling', 'other']) {
      if (mobile) state[key] = tabs.find(tab => tab.name === state.names[state[key]])?.id;
      assert(tabs.some(tab => tab.id === state[key]), `Missing restored ${key} tab`);
      await call('switch-tab', { tabId: state[key] });
      await call('navigate', { tabId: state[key], url: origin + '/probe' });
    }
    await verify();
    state.names = Object.fromEntries(tabs.map(tab => [tab.id, tab.name]));
    await writeFile(values.state, JSON.stringify(state), { mode: 0o600 });
    console.log('PASS: persistent default and isolated identities after app restart');
  }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
