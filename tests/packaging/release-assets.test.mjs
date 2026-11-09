import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { attachReleaseAssets, fileDigest } from '../../scripts/attach-release-assets.mjs';
import { validateRecovery } from '../../scripts/prepare-release-recovery.mjs';
import { taggedComponentVersion } from '../../scripts/publish-app-update.mjs';

const tag = 'release/2026-11-09.7';
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'kelpie-release-assets-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const first = join(root, 'kelpie-android-test-release.apk');
  const second = join(root, 'checksums-android.txt');
  await writeFile(first, 'verified APK fixture');
  await writeFile(second, 'checksum fixture');
  return { root, first, second };
}

test('resumes asset uploads without editing release targets or replacing completed assets', async t => {
  const { root, first, second } = await fixture(t);
  const release = { tag_name: tag, draft: false, prerelease: false, body: 'Preserve these notes',
    assets: [{ name: basename(first), state: 'uploaded', digest: await fileDigest(first) }] };
  const commands = [];
  const run = args => {
    commands.push(args);
    if (args[0] === 'api') return JSON.stringify(release);
    assert.deepEqual(args, ['release', 'upload', tag, second]);
    release.assets.push({ name: basename(second), state: 'uploaded', digest: checksumDigest });
    return '';
  };
  const checksumDigest = await fileDigest(second);
  assert.deepEqual(await attachReleaseAssets(tag, root, run), { uploaded: 1, verified: 2 });
  assert.deepEqual(await attachReleaseAssets(tag, root, run), { uploaded: 0, verified: 2 });
  assert.equal(commands.filter(args => args[0] === 'release').length, 1);
  assert.equal(release.body, 'Preserve these notes');
  assert.ok(commands.every(args => !args.includes('--method') && !args.includes('--clobber')));
});

test('refuses immutable asset conflicts and duplicate names before replacement', async t => {
  const { root, first } = await fixture(t);
  const run = args => {
    assert.equal(args[0], 'api');
    return JSON.stringify({ tag_name: tag, assets: [{ name: basename(first), state: 'uploaded', digest: 'sha256:' + '0'.repeat(64) }] });
  };
  await assert.rejects(attachReleaseAssets(tag, root, run), /Refusing to replace/);
  await mkdir(join(root, 'other'));
  await writeFile(join(root, 'other', basename(first)), 'another package');
  await assert.rejects(attachReleaseAssets(tag, root, run), /must be unique/);
});

test('does not treat an unverified upload as completed publication', async t => {
  const { root } = await fixture(t);
  const run = args => args[0] === 'api' ? JSON.stringify({ tag_name: tag, assets: [] }) : '';
  await assert.rejects(attachReleaseAssets(tag, root, run), /digest was not verified/);
});

const build = { event: 'release', workflow_id: 10, status: 'completed', head_branch: tag, head_sha: 'a'.repeat(40) };
const release = { tag_name: tag, body: '<!-- kelpie-release-components: linux android -->\n<!-- kelpie-release-component: linux -->\n<!-- kelpie-release-component: android -->' };
const artifacts = ['linux-release-ubuntu-22.04', 'linux-release-fedora-40', 'android-release'].map(name => ({ name, expired: false }));
test('recovery binds completed artifacts to the exact published tag and workflow', () => {
  const validate = (run = build, source = { sha: build.head_sha }, files = artifacts) => validateRecovery(run, { id: 10 }, release, source, files);
  assert.deepEqual(validate(), { tag, linux: true });
  assert.throws(() => validate({ ...build, event: 'pull_request' }), /release workflow/);
  assert.throws(() => validate({ ...build, workflow_id: 11 }), /release workflow/);
  assert.throws(() => validate(build, { sha: 'b'.repeat(40) }), /source revision/);
  assert.throws(() => validate(build, { sha: build.head_sha }, artifacts.slice(1)), /selected components/);
  assert.throws(() => validate(build, { sha: build.head_sha }, artifacts.map(item => ({ ...item, expired: true }))), /selected components/);
});

test('recovery advertises the version from the release tag rather than the current checkout', () => {
  const api = path => {
    assert.equal(path, 'repos/UnlikeOtherAI/kelpie/contents/apps/linux/CMakeLists.txt?ref=release%2F2026-11-09.7');
    return JSON.stringify({ content: Buffer.from('KELPIE_LINUX_VERSION="0.2.4"').toString('base64') });
  };
  assert.equal(taggedComponentVersion(api, tag, 'linux-x64-tar'), '0.2.4');
});
