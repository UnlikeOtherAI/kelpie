import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

// Run with a built CLI and a disposable native WebKit session on this host:
// node tests/native/apple-local-navigation.mjs 127.0.0.1:18523 [off-host-fixture-port]
const target = process.argv[2];
assert.match(target ?? '', /^127\.0\.0\.1:\d+$/, 'Supply the isolated WebKit control address');
const offHostPort = process.argv[3];
if (offHostPort !== undefined) assert.match(offHostPort, /^\d{1,5}$/);
const exec = promisify(execFile);
const cliPath = fileURLToPath(new URL('../../packages/cli/dist/index.js', import.meta.url));
const designerPath = '/agents/designer/f3f296a6-0f05-4e31-b970-22ca77567ac7';
const marker = 'Fixture channels storage present';
const scratch = await mkdtemp(join(tmpdir(), 'kelpie-local-navigation-'));
const requests = [];
const fixture = createServer((req, res) => {
  requests.push(req.url);
  if (req.url === designerPath) {
    res.writeHead(302, { Location: `${designerPath}?ready=1` });
    res.end();
    return;
  }
  const finish = () => {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    if (req.url === '/channels') {
      res.end(`<!doctype html><title>Fixture channels</title><h1></h1><script>
        const text = localStorage.getItem('nessie.admin.token') === 'fixture-only' ? '${marker}' : 'Fixture storage missing';
        document.querySelector('h1').textContent = text;
        console.info(text);
      </script>`);
    } else {
      res.end('<!doctype html><title>Local fixture</title><h1>Local fixture</h1>');
    }
  };
  if (req.url === `${designerPath}?stalled=1`) setTimeout(finish, 12_000);
  else if (req.url === `${designerPath}?ready=1`) setTimeout(finish, 350);
  else finish();
});

async function cli(args, expectedError) {
  const start = performance.now();
  const result = await exec(process.execPath, [cliPath, '--device', target, ...args], {
    env: { ...process.env, KELPIE_HOME: scratch },
    timeout: 35_000,
  }).catch(error => {
    if (!expectedError || !error.stdout) throw error;
    return error;
  });
  const value = JSON.parse(result.stdout);
  console.log(args[0], Math.round(performance.now() - start), 'ms', value.error ?? value.title ?? value.success);
  if (expectedError) assert.equal(value.error?.code, expectedError);
  else assert.notEqual(value.success, false, JSON.stringify(value.error));
  return value;
}

try {
  fixture.listen(0, '127.0.0.1');
  await once(fixture, 'listening');
  const { port } = fixture.address();
  const origin = `http://localhost:${port}`;
  const designer = `${origin}${designerPath}`;
  const channels = `${origin}/channels`;
  const info = await cli(['info']);
  assert.equal(info.requiresPairing, false);
  assert(['macos', 'ios'].includes(info.platform));
  if (info.platform === 'macos') assert.equal((await cli(['renderer', 'get'])).engine, 'webkit');
  await cli(['navigate', origin]);
  await cli(['eval', "localStorage.setItem('nessie.admin.token', 'fixture-only')"]);
  assert.equal((await cli([designer])).url, `${designer}?ready=1`);
  assert(requests.includes(designerPath));
  assert(requests.includes(`${designerPath}?ready=1`));
  assert.equal((await cli(['back'])).url, `${origin}/`);
  assert.equal((await cli(['forward'])).url, `${designer}?ready=1`);
  await cli(['navigate', channels]);
  const wait = await cli(['wait', 'button[aria-label*="favorite"]', '--wait-timeout', '20000'], 'TIMEOUT');
  assert.match(wait.error.message, /element.*within 20000ms/i);
  assert.equal((await cli(['url', '--timeout', '10000'])).url, channels);
  assert.match(JSON.stringify(await cli(['page-text', '--timeout', '10000'])), new RegExp(marker));
  assert.match(JSON.stringify(await cli(['console', '--timeout', '10000'])), new RegExp(marker));
  const output = join(scratch, 'fixture.png');
  const screenshot = await cli(['screenshot', '--output', output, '--timeout', '10000']);
  assert(screenshot.width > 0 && screenshot.height > 0);
  const png = await readFile(output);
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  console.log('Screenshot:', screenshot.width, '×', screenshot.height, png.length, 'bytes');

  const stalled = `${designer}?stalled=1`;
  const timeout = await cli([stalled], 'TIMEOUT');
  assert.match(timeout.error.message, /navigation.*within 10000ms/i);
  assert.equal((await cli(['wait-nav'])).url, stalled);

  // The optional port can be serving this path on a different computer.
  // Either way, there must be no listener on this browser's loopback.
  const closed = once(fixture, 'close');
  fixture.close();
  fixture.closeAllConnections();
  await closed;
  const destination = offHostPort ? `http://localhost:${offHostPort}${designerPath}` : designer;
  const failed = await cli([destination], 'NAVIGATION_ERROR');
  assert.match(failed.error.message, /loopback.*device running Kelpie/i);
  const waitNav = await cli(['wait-nav'], 'NAVIGATION_ERROR');
  assert.equal(waitNav.error.message, failed.error.message);
  await cli(['url']);
  fixture.listen(port, '127.0.0.1');
  await once(fixture, 'listening');
  await cli(['navigate', channels]);
  assert.equal((await cli(['wait-nav'])).url, channels);
} finally {
  fixture.closeAllConnections();
  fixture.close();
  await rm(scratch, { recursive: true, force: true });
}
