import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const script = join(repository, 'scripts/build-linux-runtime-bundle.sh');
const legacyFiles = ['libEGL.so', 'libGLESv2.so', 'snapshot_blob.bin'];

function fixture(t, legacy = false) {
  const cache = join(repository, '.cache');
  mkdirSync(cache, { recursive: true });
  const root = mkdtempSync(join(cache, 'linux-runtime-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const sdk = join(root, 'sdk');
  const build = join(root, 'apps/linux/build');
  for (const directory of ['sdk/Release', 'sdk/Resources/locales', 'sdk/Resources/new-data', 'source', 'packaging/linux']) {
    mkdirSync(join(root, directory), { recursive: true });
  }
  for (const name of ['chrome-sandbox', 'libcef.so', 'libvulkan.so.1', 'new-runtime.so', ...(legacy ? legacyFiles : [])]) {
    writeFileSync(join(sdk, 'Release', name), `runtime:${name}`);
  }
  writeFileSync(join(sdk, 'Resources/locales/en-US.pak'), 'locale');
  writeFileSync(join(sdk, 'Resources/new-data/shader.bin'), 'shader');
  writeFileSync(join(sdk, 'Resources/resources.pak'), 'resources');
  writeFileSync(join(root, 'source/main.c'), 'int main(void) { return 0; }\n');
  writeFileSync(join(root, 'source/CMakeLists.txt'), `cmake_minimum_required(VERSION 3.16)
project(runtime_fixture C)
add_executable(kelpie-linux main.c)
include("${repository}/apps/linux/cmake/cef_runtime.cmake")
kelpie_stage_cef_runtime(kelpie-linux "${sdk}")
`);
  execFileSync('cmake', ['-S', join(root, 'source'), '-B', build, '-G', 'Unix Makefiles'], { encoding: 'utf8' });
  execFileSync('cmake', ['--build', build], { encoding: 'utf8' });
  copyFileSync(join(repository, 'packaging/linux/runtime-files.txt'), join(root, 'packaging/linux/runtime-files.txt'));
  for (const name of ['FontAwesome6Brands-Regular.otf', 'icon-1024.png', 'install-update.sh']) {
    writeFileSync(join(build, name), `asset:${name}`);
  }
  return { root, build, bundle: join(root, 'output/kelpie-linux'),
    package: () => spawnSync('bash', [script, '--version', 'test', '--output-dir', 'output'], { cwd: root, encoding: 'utf8' }) };
}

test('packages new CEF entries and excludes retired files left in the build directory', { skip: process.platform !== 'linux' }, t => {
  const f = fixture(t);
  writeFileSync(join(f.build, 'libEGL.so'), 'stale file from an earlier SDK');
  const result = f.package();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.ok(existsSync(join(f.bundle, 'new-runtime.so')));
  assert.equal(readFileSync(join(f.bundle, 'new-data/shader.bin'), 'utf8'), 'shader');
  assert.equal(readFileSync(join(f.bundle, 'locales/en-US.pak'), 'utf8'), 'locale');
  assert.ok(!existsSync(join(f.bundle, 'libEGL.so')));
  assert.equal(readFileSync(join(f.bundle, 'cef-runtime-files.txt'), 'utf8'), readFileSync(join(f.build, 'cef-runtime-files.txt'), 'utf8'));
  execFileSync(join(f.bundle, 'kelpie-linux'));
});

test('older SDKs retain their additional libraries and snapshots', { skip: process.platform !== 'linux' }, t => {
  const f = fixture(t, true);
  const result = f.package();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  for (const name of legacyFiles) assert.equal(readFileSync(join(f.bundle, name), 'utf8'), `runtime:${name}`);
});

test('missing staged files or manifest fail without replacing an existing bundle', { skip: process.platform !== 'linux' }, t => {
  const f = fixture(t);
  mkdirSync(f.bundle, { recursive: true });
  writeFileSync(join(f.bundle, 'previous'), 'keep existing output');
  rmSync(join(f.build, 'new-runtime.so'));
  const missingFile = f.package();
  assert.notEqual(missingFile.status, 0);
  assert.match(missingFile.stderr, /Missing runtime file/);
  assert.equal(readFileSync(join(f.bundle, 'previous'), 'utf8'), 'keep existing output');
  rmSync(join(f.build, 'cef-runtime-files.txt'));
  const missingManifest = f.package();
  assert.notEqual(missingManifest.status, 0);
  assert.match(missingManifest.stderr, /Missing CEF runtime manifest/);
  assert.ok(existsSync(join(f.bundle, 'previous')));
});

test('runtime manifests cannot copy files outside the staged directory', { skip: process.platform !== 'linux' }, t => {
  const f = fixture(t);
  writeFileSync(join(f.build, 'cef-runtime-files.txt'), '../outside\n');
  const result = f.package();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Invalid runtime file name/);
  assert.ok(!existsSync(f.bundle));
});
