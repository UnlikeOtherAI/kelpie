import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:http';

// Run with a disposable emulator, forwarding its Kelpie port and reversing tcp:18530.
// Leave port 18531 unused on the emulator.
const target = process.argv[2];
assert.match(target ?? '', /^127\.0\.0\.1:\d+$/, 'Supply the forwarded Kelpie control address');
const fixturePort = 18530;
const unavailable = 'http://127.0.0.1:18531/agents/designer/fixture';
const healthy = `http://127.0.0.1:${fixturePort}`;
const fixture = createServer((request, response) => {
  if (request.url === '/missing.png') {
    response.writeHead(404).end();
    return;
  }
  response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  response.end('<!doctype html><title>Local navigation fixture</title><img src="/missing.png" alt="">');
});

async function command(route, params = {}, expectedError) {
  const response = await fetch(`http://${target}/v1/${route}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(20_000),
  });
  const result = await response.json();
  console.log(route, response.status, result.error?.code ?? result.url ?? result.success);
  if (expectedError) {
    assert.equal(result.error?.code, expectedError, JSON.stringify(result));
    assert.equal(response.status, 502);
  } else {
    assert.equal(result.success, true, JSON.stringify(result));
  }
  return result;
}

try {
  fixture.listen(fixturePort, '127.0.0.1');
  await once(fixture, 'listening');
  const { activeTab: first } = await command('get-tabs');
  assert(first);
  await command('navigate', { url: `${healthy}/first` });
  assert.equal((await command('wait-for-navigation')).url, `${healthy}/first`);
  const { tabId: second } = await command('new-tab');
  assert(second && second !== first);
  await command('switch-tab', { tabId: second });
  await command('navigate', { url: `${healthy}/second` });

  const failed = await command('navigate', { url: unavailable }, 'NAVIGATION_ERROR');
  const waiting = await command('wait-for-navigation', {}, 'NAVIGATION_ERROR');
  assert.match(failed.error.message, /loopback.*device running Kelpie/i);
  assert.equal(waiting.error.message, failed.error.message);

  await command('switch-tab', { tabId: first });
  assert.equal((await command('wait-for-navigation')).url, `${healthy}/first`);
  await command('switch-tab', { tabId: second });
  const persistent = await command('wait-for-navigation', {}, 'NAVIGATION_ERROR');
  assert.equal(persistent.error.message, failed.error.message);

  await command('navigate', { url: `${healthy}/recovered` });
  assert.equal((await command('wait-for-navigation')).url, `${healthy}/recovered`);
} finally {
  fixture.close();
  fixture.closeAllConnections();
}
