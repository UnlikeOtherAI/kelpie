import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const binary = process.env.KELPIE_LINUX_BINARY;

test('compiled Linux CEF entry point permits Chromium to rotate the stack guard', {
  skip: !binary || process.platform !== 'linux' || process.arch !== 'x64',
}, () => {
  const assembly = execFileSync('objdump', ['-d', '--disassemble=main', resolve(binary)], { encoding: 'utf8' });
  assert.match(assembly, /CefExecuteProcess/, 'Inspect the real CEF entry point, not a stub build');
  assert.doesNotMatch(assembly, /__stack_chk_fail/, 'main must not compare a pre-fork stack guard after CEF returns');
});

test('real Linux CEF renders, clicks and closes child processes without stack-guard aborts', {
  skip: !binary || process.platform !== 'linux', timeout: 60_000,
}, async () => {
  await mkdir('.cache', { recursive: true });
  const profile = await mkdtemp(resolve('.cache/cef-runtime-'));
  const server = createServer((_request, response) => {
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><title>CEF runtime verification</title><h1>Ready</h1>' +
      '<button onclick="document.querySelector(\'h1\').textContent=\'Clicked\'">Verify click</button>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const executable = resolve(binary);
  const child = spawn(executable, ['--headless', '--port', '0', '--profile-dir', profile, '--url', url], {
    cwd: dirname(executable), stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  let closed = false;
  const completion = new Promise(resolve => {
    child.once('error', error => { closed = true; resolve({ error: error.message }); });
    child.once('close', (code, signal) => { closed = true; resolve({ code, signal }); });
  });
  const waitFor = async (operation, description) => {
    const deadline = Date.now() + 15_000;
    while (Date.now() < deadline && !closed) {
      const value = await operation();
      if (value) return value;
      await delay(100);
    }
    throw new Error(`Timed out waiting for ${description}; process closed=${closed}\n${output}`);
  };
  try {
    const ready = await waitFor(async () => {
      try { return JSON.parse(await readFile(join(profile, 'readiness.json'), 'utf8')); }
      catch (error) { if (error.code === 'ENOENT' || error instanceof SyntaxError) return null; throw error; }
    }, 'readiness');
    const call = async (method, tabId, params) => {
      const response = await fetch(`http://127.0.0.1:${ready.port}/v1/browser-control`, {
        method: 'POST', headers: { Authorization: `Bearer ${ready.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ version: 1, method, tabId, params }), signal: AbortSignal.timeout(10_000),
      });
      assert.equal(response.status, 200);
      const result = await response.json();
      assert.equal(result.ok, true, JSON.stringify(result));
      return result.value;
    };
    const tabs = await waitFor(async () => {
      const found = await call('tabs.list');
      return found.some(tab => tab.title === 'CEF runtime verification') && found;
    }, 'rendered fixture');
    const tabId = tabs.find(tab => tab.title === 'CEF runtime verification').id;
    const snapshot = await call('tab.snapshot', tabId);
    const button = snapshot.elements.find(element => element.role === 'button' && element.name === 'Verify click');
    assert.ok(button, 'Real renderer exposes the fixture button');
    await call('tab.click', tabId, { ref: button.ref });
    await waitFor(async () => (await call('tab.snapshot', tabId)).text.includes('Clicked'), 'click result');
    const screenshot = await call('tab.screenshot', tabId, { format: 'png' });
    assert.equal(screenshot.mimeType, 'image/png');
    assert.ok(Buffer.from(screenshot.data, 'base64').length > 100);
    for (let index = 0; index < 3; index++) {
      const created = await call('tabs.new', undefined, { url });
      assert.ok(created.id, 'New tab has an id');
      await waitFor(async () => (await call('tab.title', created.id)) === 'CEF runtime verification', 'new tab');
      await call('tabs.close', created.id);
    }
    child.kill('SIGTERM');
    const exit = await Promise.race([completion, delay(10_000, null, { ref: false })]);
    assert.ok(exit, 'Browser exits after SIGTERM');
    assert.deepEqual(exit, { code: 0, signal: null }, output);
    assert.doesNotMatch(output, /stack smashing|__stack_chk_fail|Aborted \(core dumped\)/i);
  } finally {
    if (!closed) { child.kill('SIGKILL'); await completion; }
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await rm(profile, { recursive: true, force: true });
  }
});
