import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { PLATFORMS, compareCef, latestStable, verifyArchive, chromeStable } from '../../scripts/engine-updates/upstream.mjs';
import { FILES, readSources, readPins, planUpdates, updateSources } from '../../scripts/engine-updates/pins.mjs';

const current = '150.0.2+g123abcd+chromium-150.0.7800.9';
const newer = '156.0.11+g456abcd+chromium-156.0.8000.10';
const sha1 = 'a'.repeat(40);
const sha256 = 'b'.repeat(64);
function version(cef = newer, platform = 'windows64', channel = 'stable') {
  return { cef_version: cef, chromium_version: cef.split('chromium-')[1], channel,
    files: [{ type: 'minimal', name: `cef_binary_${cef}_${platform}_minimal.tar.bz2`,
      sha1, size: 5, last_modified: '2026-11-18T00:00:00Z' }] };
}
function sources() {
  return {
    [FILES[0]]: `#!/bin/bash\ninstall_macos_arm64() {\n    local cef_version="${current}"\n}\ninstall_linux_x64() {\n    local cef_version="${current}"\n}\n`,
    [FILES[1]]: `$version = "${current}"\n$expectedSha1 = "${sha1}"\n$expectedSha256 = "${sha256}"\n`,
    [FILES[2]]: `$CefRoot = "cache/cef_binary_${current}_windows64_minimal"\n$cefVersion = "${current}"\n`,
    [FILES[3]]: `CEF_VERSION="\${1:-${current}}"\n`,
    [FILES[4]]: `ARG CEF_VERSION=${current}\n`,
  };
}
function plan(platforms = PLATFORMS) {
  return platforms.map(platform => ({ platform, current, cef: newer, chromium: '156.0.8000.10',
    sha1: 'c'.repeat(40), sha256: 'd'.repeat(64), update: true }));
}

test('latest stable sorts numerically, ignoring recent older maintenance releases and beta', () => {
  const futureBeta = '157.0.1+g123abcd+chromium-157.0.9000.1';
  const index = { windows64: { versions: [version(current), version(futureBeta, 'windows64', 'beta'), version(newer),
    { channel: 'stable', cef_version: '3.3683.1920.g9f41a27' }] } };
  assert.equal(latestStable(index, 'windows64').cef, newer);
  assert.ok(compareCef('156.0.10+g123abcd+chromium-156.0.8000.10', '156.0.9+g123abcd+chromium-156.0.8000.10') > 0);
});

test('missing archives, untrusted names, mismatched versions and malformed metadata fail closed', () => {
  assert.throws(() => latestStable({}, 'windows64'), /Missing/);
  for (const mutate of [v => { v.files = []; }, v => { v.files[0].name = '../../download'; },
    v => { v.chromium_version = '999.0.0.0'; }, v => { v.files[0].sha1 = 'bad'; },
    v => { v.files[0].size = -1; }, v => { v.files[0].last_modified = 'bad'; }]) {
    const row = version(); mutate(row);
    assert.throws(() => latestStable({ windows64: { versions: [row] } }, 'windows64'));
  }
});

test('never downgrade or rewrite an equal source pin', () => {
  const candidates = PLATFORMS.map(platform => ({ platform, cef: current }));
  const result = planUpdates(Object.fromEntries(PLATFORMS.map(p => [p, newer])), candidates);
  assert.ok(result.every(p => !p.update));
  const equal = planUpdates(readPins(sources()), candidates);
  assert.ok(equal.every(p => !p.update));
  assert.deepEqual(updateSources(sources(), equal), {});
});

test('all platform consumers change together and Windows retains both verified checksums', () => {
  const input = sources();
  const output = { ...input, ...updateSources(input, plan()) };
  assert.deepEqual(readPins(output), Object.fromEntries(PLATFORMS.map(p => [p, newer])));
  assert.ok(output[FILES[1]].includes('C'.repeat(40)));
  assert.ok(output[FILES[1]].includes('D'.repeat(64)));
  assert.equal(input[FILES[0]], sources()[FILES[0]]);
});

test('one platform can change when Mac and Linux share the old pin', () => {
  const input = sources();
  const output = { ...input, ...updateSources(input, plan(['macosarm64'])) };
  assert.deepEqual(readPins(output), { macosarm64: newer, linux64: current, windows64: current });
  assert.equal(output[FILES[1]], input[FILES[1]]);
  assert.equal(output[FILES[4]], input[FILES[4]]);
});

test('Linux updates both download and Docker pins without changing Mac or Windows', () => {
  const input = sources();
  const output = { ...input, ...updateSources(input, plan(['linux64'])) };
  assert.deepEqual(readPins(output), { macosarm64: current, linux64: newer, windows64: current });
  assert.equal(output[FILES[4]], `ARG CEF_VERSION=${newer}\n`);
  assert.equal(output[FILES[3]], input[FILES[3]]);
  assert.equal(output[FILES[1]], input[FILES[1]]);
});

test('pin drift and missing verified hashes stop the update', () => {
  const input = sources();
  assert.throws(() => readPins({ ...input, [FILES[2]]: input[FILES[2]].replace(current, newer) }), /disagree/);
  assert.throws(() => readPins({ ...input, [FILES[4]]: input[FILES[4]].replace(current, newer) }), /disagree/);
  assert.throws(() => readPins({ ...input, [FILES[4]]: '' }), /Expected one Linux Docker pin/);
  assert.throws(() => updateSources(input, plan().map(p => ({ ...p, sha256: undefined }))), /SHA-256/);
});

test('current repository pins have every expected consumer and can be planned without writing', () => {
  const input = readSources();
  const pins = readPins(input);
  const candidates = PLATFORMS.map(platform => ({ platform, current: pins[platform],
    cef: '999.0.1+g123abcd+chromium-999.0.9000.1', sha1, sha256, update: true }));
  const result = updateSources(input, candidates);
  assert.equal(Object.keys(result).length, FILES.length);
  assert.equal(readPins({ ...input, ...result }).windows64, candidates[0].cef);
});

test('archive verification streams bytes and rejects truncation, oversized data and tampering', async () => {
  const bytes = Buffer.from('hello');
  const candidate = { url: 'https://cef-builds.spotifycdn.com/cef_binary_test', size: bytes.length,
    sha1: createHash('sha1').update(bytes).digest('hex') };
  const fetcher = async () => new Response(bytes);
  assert.equal(await verifyArchive(candidate, fetcher), createHash('sha256').update(bytes).digest('hex'));
  await assert.rejects(verifyArchive({ ...candidate, size: 6 }, fetcher), /mismatch/);
  await assert.rejects(verifyArchive({ ...candidate, size: 4 }, fetcher), /exceeds/);
  await assert.rejects(verifyArchive({ ...candidate, sha1 }, fetcher), /mismatch/);
  await assert.rejects(verifyArchive(candidate, async () => new Response('', { status: 503 })), /503/);
  await assert.rejects(verifyArchive({ ...candidate, url: 'https://untrusted.example/archive' }, fetcher), /host/);
});

test('Chrome stable uses the platform-specific official feed and rejects missing data', async () => {
  let url;
  const result = await chromeStable('macosarm64', async input => {
    url = input; return Response.json({ versions: [{ version: '156.0.8000.10' }] });
  });
  assert.match(url, /platforms\/mac_arm64\/channels\/stable/);
  assert.equal(result.version, '156.0.8000.10');
  await assert.rejects(chromeStable('linux64', async () => Response.json({})), /Missing/);
});
