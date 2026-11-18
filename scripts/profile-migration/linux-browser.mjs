import { spawn } from 'node:child_process';
import { readFile, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

export async function call(ready, method, body) {
  const response = await fetch(`http://127.0.0.1:${ready.port}/v1/${method}`, {
    method: 'POST', headers: { Authorization: `Bearer ${ready.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`Browser migration API returned HTTP ${response.status}`);
  const result = await response.json();
  if (result.success !== true) throw new Error('Browser migration API failed');
  return result;
}

export async function startBrowser(binary, profile, url = 'about:blank') {
  await rm(join(profile, 'readiness.json'), { force: true });
  const child = spawn(binary, ['--headless', '--port', '0', '--profile-dir', profile, '--url', url], {
    cwd: dirname(binary), stdio: 'ignore',
  });
  let exited = false;
  const completion = new Promise(resolve => {
    child.once('error', () => { exited = true; resolve(false); });
    child.once('exit', code => { exited = true; resolve(code === 0); });
  });
  const stop = async () => {
    if (exited) throw new Error('Migration browser exited unexpectedly');
    child.kill('SIGTERM');
    const clean = await Promise.race([completion, delay(15_000, false, { ref: false })]);
    if (!clean) throw new Error('Migration browser did not shut down cleanly; original profile is retained');
  };
  try {
    for (let attempt = 0; attempt < 200 && !exited; attempt++) {
      try {
        const ready = JSON.parse(await readFile(join(profile, 'readiness.json'), 'utf8'));
        if (Number.isInteger(ready.port) && ready.port > 0 && typeof ready.token === 'string') {
          await call(ready, 'get-cookies', { all: true });
          return { ready, stop };
        }
      } catch { /* Startup publishes readiness before the first browser exists. */ }
      await delay(100);
    }
    throw new Error('Migration browser did not become ready; close other Kelpie instances first');
  } catch (error) {
    if (!exited) await stop();
    throw error;
  }
}

export async function lockProfile(profile) {
  // Match ProfileSession's flock, held until stdin closes. No interpolated shell text.
  const child = spawn('flock', ['--exclusive', '--nonblock', join(profile, 'profile.lock'),
    'sh', '-c', 'printf locked; cat >/dev/null'], { stdio: ['pipe', 'pipe', 'ignore'] });
  const acquired = await new Promise(resolve => {
    child.stdout.once('data', data => resolve(data.toString() === 'locked'));
    child.once('error', () => resolve(false));
    child.once('exit', () => resolve(false));
  });
  if (!acquired) throw new Error('Profile is in use; close Kelpie before migrating');
  return async () => {
    const exited = new Promise(resolve => child.once('exit', resolve));
    child.stdin.end();
    await exited;
  };
}
