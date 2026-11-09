import assert from 'node:assert/strict';
import test from 'node:test';
import { marker, updateNotes, componentVersion } from '../../scripts/publish-app-update.mjs';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';

const digest = 'a'.repeat(64);
const release = { draft: false, prerelease: false, body: '<!-- kelpie-release-components: windows -->\n\nWindows 0.2.1',
  assets: [{ name: 'Kelpie-windows-0.2.1-x64.zip', state: 'uploaded', digest: `sha256:${digest}`,
    browser_download_url: 'https://github.com/UnlikeOtherAI/kelpie/releases/download/release/2026-11-09/Kelpie-windows-0.2.1-x64.zip' }] };
const options = { target: 'windows-x64', version: '0.2.1', asset: release.assets[0].name };

test('takes the component version from the tagged source manifest', () => {
  assert.equal(componentVersion('project(kelpie_windows VERSION 0.2.1 LANGUAGES CXX RC)', 'windows-x64'), '0.2.1');
  assert.equal(componentVersion('<key>CFBundleShortVersionString</key>\n<string>0.2.1</string>', 'macos-arm64'), '0.2.1');
  assert.equal(componentVersion('KELPIE_LINUX_VERSION="0.2.1"', 'linux-x64-tar'), '0.2.1');
  assert.throws(() => componentVersion('release/2026-11-09', 'windows-x64'));
});

test('publishes a ready component and preserves release selection and notes', () => {
  const body = updateNotes(release, options);
  assert.ok(body.startsWith(release.body));
  assert.deepEqual(JSON.parse(body.split(marker)[1].split(' -->')[0]), {
    target: options.target, version: options.version, url: release.assets[0].browser_download_url, sha256: digest,
  });
  assert.equal(updateNotes({ ...release, body }, options), body);
});
test('preserves another platform and replaces only the selected target', () => {
  const ios = updateNotes(release, { target: 'ios', version: '0.2.1', storeURL: 'https://apps.apple.com/app/id123456789' });
  const body = updateNotes({ ...release, body: ios }, options);
  assert.ok(body.includes('"target":"ios"'));
  assert.equal(body.split(marker).length, 3);
});
test('refuses incomplete, unsigned-digest, unrelated and incompatible assets', () => {
  for (const change of [{ draft: true }, { prerelease: true }, { assets: [] },
    { assets: [{ ...release.assets[0], state: 'new' }] },
    { assets: [{ ...release.assets[0], digest: null }] },
    { assets: [{ ...release.assets[0], browser_download_url: 'https://example.com/update.zip' }] }]) {
    assert.throws(() => updateNotes({ ...release, ...change }, options));
  }
  assert.throws(() => updateNotes(release, { ...options, version: 'release/2026-11-09' }));
  assert.throws(() => updateNotes(release, { ...options, target: 'ios' }));
  assert.throws(() => updateNotes(release, { ...options, storeURL: 'https://example.com' }));
});

test('the real Windows helper refuses unsafe metadata before closing or changing an app',
  { skip: process.platform !== 'win32', timeout: 30_000 }, async () => {
    const directory = await mkdtemp(join(tmpdir(), 'kelpie-update-refusal-'));
    const request = join(directory, 'request.json');
    await writeFile(request, JSON.stringify({ url: 'file:///untrusted.zip', sha256: digest, version: '0.2.1' }));
    const powershell = join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    await assert.rejects(promisify(execFile)(powershell, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', resolve('apps/updates/install-windows.ps1'), '-RequestPath', request], { timeout: 20_000 }));
    assert.equal(await readFile(join(directory, 'status'), 'utf8'), 'error');
    assert.match(await readFile(join(directory, 'error'), 'utf8'), /Invalid update metadata/);
  });
