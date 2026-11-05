import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { runG08 } from './android-native-g08.mjs';

const execute = promisify(execFile);
const [root, folder, port, profile, revision, binarySHA256] = process.argv.slice(2);
const cli = resolve(root, 'packages/cli/bin/kelpie.js');
async function command(name, args) {
  const { stdout } = await execute(process.execPath, [cli, '--device', '127.0.0.1',
    '--port', port, '--timeout', '180000', ...args], { timeout: 200000, maxBuffer: 4 * 1024 * 1024 });
  const value = JSON.parse(stdout);
  // CLI pairing output contains scope/device metadata, never the bearer.
  await writeFile(join(folder, name + '.json'), JSON.stringify(value, null, 2) + '\n');
  return value;
}
const bridge = JSON.parse(await readFile(join(folder, 'cli-bridge.json'), 'utf8'));
const paired = await command('cli-pair', ['pair', '--client-name', 'Hosted native CLI verification', '--timeout-ms', '60000']);
assert.equal(paired.success, true);
assert.equal(paired.persisted, true);
assert.equal((await command('cli-navigate', ['navigate', bridge.url])).success, true);
const readyUntil = Date.now() + 60000;
let ready = false;
while (!ready && Date.now() < readyUntil) {
  const title = await command('cli-new-document-title', ['browser-control', JSON.stringify({
    version: 1, method: 'tab.title', tabId: bridge.tabId, params: {},
  })]);
  const state = await command('cli-new-document-ready', ['browser-control', JSON.stringify({
    version: 1, method: 'tab.ready', tabId: bridge.tabId, params: { selector: '#pixels', state: 'complete' },
  })]);
  ready = title.ok === true && title.value === 'Noise ready' && state.ok === true && state.value.ready === true;
  if (!ready) await new Promise(resolveReady => setTimeout(resolveReady, 50));
}
assert.equal(ready, true, 'New canvas document must finish drawing before capture starts');
const script = {
  version: 1, tabId: bridge.tabId,
  capture: { formats: ['screenshots'], maxWidth: 640, maxBytes: 16777216 },
  actions: [{ action: 'wait-ready', state: 'complete', selector: '#pixels', timeoutMs: 10000 },
    { action: 'screenshot' }],
};
const scriptFile = join(folder, 'cli-script.json');
await writeFile(scriptFile, JSON.stringify(script));
const run = await command('cli-run', ['script', 'run', scriptFile]);
assert.equal(run.success, true);
assert.ok(run.runId);
assert.ok(run.artifacts.length);
const status = await command('cli-status', ['script', 'status', '--run-id', run.runId, '--pinned']);
assert.equal(status.runId, run.runId);
assert.equal(status.state, 'completed');
assert.equal(status.runSuccess, true);
assert.equal(Object.hasOwn(status, 'outputs'), false);
const artifact = run.artifacts.filter(item => item.mimeType === 'image/png').sort((a, b) => b.byteLength - a.byteLength)[0];
assert.ok(artifact, 'Expected a retained PNG, including negative tiny captures');
const exports = join(folder, 'script-acceptance');
await mkdir(exports, { recursive: true });
const destination = join(exports, 'cli-' + artifact.id + '.png');
await command('cli-download', ['script', 'download', run.runId, artifact.id, destination]);
const bytes = await readFile(destination);
assert.equal(bytes.length, artifact.byteLength);
assert.equal(createHash('sha256').update(bytes).digest('hex'), artifact.sha256);
assert.ok(artifact.byteLength > 262144, 'Expected PNG spanning the canonical artifact chunk boundary');
await writeFile(join(folder, 'cli-report.json'), JSON.stringify({
  success: true, transport: 'authenticated public CLI', runId: run.runId,
  sha256: artifact.sha256, byteLength: bytes.length, sourceRevision: process.env.GITHUB_SHA,
}, null, 2) + '\n');
await runG08({ command, folder, tabId: bridge.tabId, profile, revision, binarySHA256 });
