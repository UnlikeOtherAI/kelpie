import { test } from 'node:test';
import { deepStrictEqual, strictEqual } from 'node:assert';
import { publicHistoryDiagnostic } from './public-history-diagnostic.mjs';

test('one public mutation per history case and fixed insufficient limits', async () => {
  const origin = 'http://127.0.0.1:1234'; let url = ''; const calls = [];
  const lifecycle = { mark: () => 1, result: () => ({ status: 'restored-from-bfcache' }), hashResult: () => ({ status: 'observed' }) };
  const call = async (method, params) => {
    calls.push(method);
    if (method === 'tab.goto') url = params.url;
    if (method === 'tab.back') url = url.endsWith('#two') ? origin + '/next#one' : origin + '/';
    if (method === 'tab.forward') url = url.endsWith('#one') ? origin + '/next#two' : origin + '/next';
    if (method === 'tab.url') return { ok: true, value: url };
    if (method === 'tab.ready') return { ok: true, value: { ready: true, documentState: 'complete' } };
    return { ok: true, value: null };
  };
  const result = await publicHistoryDiagnostic({ call, origin, lifecycle, delay: async () => undefined });
  strictEqual(result.complete, true);
  strictEqual(calls.filter(x => x === 'tab.back').length, 2);
  strictEqual(calls.filter(x => x === 'tab.forward').length, 2);
  deepStrictEqual(result.limitations, { noHistory: 'insufficient', iframe: 'insufficient', replacement: 'insufficient', rawDispatchCount: 'not-observed' });
});

test('failed public call is not retried', async () => {
  let count = 0;
  const result = await publicHistoryDiagnostic({ call: async () => { count++; return { ok: false }; }, origin: 'http://127.0.0.1:1234', lifecycle: {}, delay: async () => undefined });
  strictEqual(count, 1); strictEqual(result.complete, false);
});

test('missing BFCache evidence cannot pass', async () => {
  const origin = 'http://127.0.0.1:1234'; let url = '';
  const call = async (method, params) => {
    if (method === 'tab.goto') url = params.url;
    if (method === 'tab.back') url = url.endsWith('#two') ? origin + '/next#one' : origin + '/';
    if (method === 'tab.forward') url = url.endsWith('#one') ? origin + '/next#two' : origin + '/next';
    return { ok: true, value: method === 'tab.url' ? url : method === 'tab.ready' ? { ready: true, documentState: 'complete' } : null };
  };
  const result = await publicHistoryDiagnostic({ call, origin, lifecycle: { mark: () => 0, result: () => ({ status: 'insufficient' }), hashResult: () => ({ status: 'observed' }) }, delay: async () => undefined });
  strictEqual(result.complete, false);
});
