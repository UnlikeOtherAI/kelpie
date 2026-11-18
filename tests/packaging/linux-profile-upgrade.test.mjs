import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { access, mkdir, mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import { createServer } from 'node:http';
import { join, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { migrate } from '../../scripts/migrate-linux-profile.mjs';
import { lockProfile, startBrowser } from '../../scripts/profile-migration/linux-browser.mjs';

const oldBinary = process.env.KELPIE_LEGACY_LINUX_BINARY;
const newBinary = process.env.KELPIE_LINUX_BINARY;

test('real CEF 120 cookie survives migration, restart, HTTP delivery and interrupted rename recovery', {
  skip: process.platform !== 'linux' || !oldBinary || !newBinary, timeout: 120_000,
}, async () => {
  await mkdir('.cache', { recursive: true });
  const root = await mkdtemp(resolve('.cache/profile-upgrade-'));
  const profile = join(root, 'profile');
  await mkdir(profile);
  let setSeen = false;
  let delivered = false;
  const server = createServer((request, response) => {
    if (request.url === '/set') {
      response.setHeader('Set-Cookie', 'kelpie_upgrade_probe=preserved; Max-Age=86400; Path=/; HttpOnly; SameSite=Lax');
      setSeen = true;
    }
    if (request.url === '/check') delivered = request.headers.cookie?.includes('kelpie_upgrade_probe=preserved') ?? false;
    response.end('<title>Profile upgrade verification</title>Verified');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  const waitFor = async condition => {
    for (let attempt = 0; attempt < 100; attempt++) {
      if (condition()) return;
      await delay(100);
    }
    assert.fail('The test server did not observe the expected cookie request');
  };
  let browser;
  try {
    browser = await startBrowser(resolve(oldBinary), profile, `${url}/set`);
    await waitFor(() => setSeen);
    await delay(200); // Let the response reach the old renderer before shutdown.
    await browser.stop(); browser = null;
    const originalCookies = await readFile(join(profile, 'cef-cache/Cookies'));
    const digest = createHash('sha256');
    for await (const chunk of createReadStream(newBinary)) digest.update(chunk);
    const options = { oldBinary: resolve(oldBinary), newBinary: resolve(newBinary), profile, newSha256: digest.digest('hex') };
    await assert.rejects(migrate({ ...options, newSha256: '0'.repeat(64) }), /SHA-256/);
    assert.deepEqual(await readFile(join(profile, 'cef-cache/Cookies')), originalCookies);
    const unlock = await lockProfile(profile);
    try { await assert.rejects(migrate(options), /Profile is in use/); } finally { await unlock(); }
    await symlink(root, join(profile, 'external-storage'));
    await assert.rejects(migrate(options), /Profile contains a symlink/);
    await rm(join(profile, 'external-storage'));
    const result = await migrate(options);
    assert.equal(result.status, 'migrated');
    assert.equal(result.cookies, 1);
    assert.deepEqual(await readFile(join(result.backup, 'cef-cache/Cookies')), originalCookies);
    browser = await startBrowser(resolve(newBinary), profile, `${url}/check`);
    await waitFor(() => delivered);
    await browser.stop(); browser = null;
    assert.equal((await migrate(options)).status, 'already-migrated');
    // Reproduce the crash window between the two final renames using a fresh
    // original copy, then rerun the supported command and verify it self-recovers.
    await rm(profile, { recursive: true });
    const recovered = await migrate(options);
    assert.equal(recovered.status, 'migrated');
    await access(join(profile, '.kelpie-chromium-upgrade.json'));
    await access(recovered.backup);
  } finally {
    if (browser) await browser.stop();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});
