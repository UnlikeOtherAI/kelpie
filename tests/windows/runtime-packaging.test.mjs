import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const legacyFiles = ['dxil.dll', 'libEGL.dll', 'libGLESv2.dll'];
const psQuote = value => `'${value.replaceAll("'", "''")}'`;

function powershell(source) {
  return spawnSync('pwsh.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand',
    Buffer.from(source, 'utf16le').toString('base64')], { encoding: 'utf8' });
}

function fixture(t, legacy = false) {
  const cache = join(repository, '.cache');
  mkdirSync(cache, { recursive: true });
  const root = mkdtempSync(join(cache, 'windows-runtime-test-'));
  assert.ok(root.startsWith(cache + sep));
  t.after(() => rmSync(root, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 }));
  const sdk = join(root, 'sdk');
  const build = join(root, 'build');
  const output = join(root, 'package');
  for (const dir of ['sdk/Release', 'sdk/Resources/locales', 'source']) mkdirSync(join(root, dir), { recursive: true });
  for (const name of ['libcef.dll', 'chrome_elf.dll', 'dxcompiler.dll', 'new-runtime.dll', 'debug.pdb', 'static.lib', ...(legacy ? legacyFiles : [])]) {
    writeFileSync(join(sdk, 'Release', name), `runtime:${name}`);
  }
  writeFileSync(join(sdk, 'Resources/resources.pak'), 'resources');
  writeFileSync(join(sdk, 'Resources/locales/en-US.pak'), 'locale');
  writeFileSync(join(root, 'source/CMakeLists.txt'), `cmake_minimum_required(VERSION 3.16)
project(runtime_fixture NONE)
set(CEF_ROOT "${sdk.replaceAll('\\', '/')}")
add_library(kelpie_engine_chromium_desktop INTERFACE)
include("${repository.replaceAll('\\', '/')}/core/windows/runtime.cmake")
add_custom_target(consumer_one ALL)
add_custom_target(consumer_two ALL)
kelpie_stage_browser_runtime(consumer_one)
kelpie_stage_browser_runtime(consumer_two)
`);
  execFileSync('cmake.exe', ['-S', join(root, 'source'), '-B', build, '-G', 'Visual Studio 17 2022'], { encoding: 'utf8' });
  execFileSync('cmake.exe', ['--build', build, '--config', 'Release', '--parallel', '2'], { encoding: 'utf8' });
  const copy = () => powershell(`$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. ${psQuote(join(repository, 'scripts/native/windows-runtime.ps1'))}
Copy-CefRuntimeFiles -BuildDir ${psQuote(build)} -Destination ${psQuote(output)}
`);
  return { root, build, output, copy };
}

test('shared staging and packaging include current SDK files and exclude stale/development files', { skip: process.platform !== 'win32' }, t => {
  const f = fixture(t);
  writeFileSync(join(f.build, 'dxil.dll'), 'stale');
  const result = f.copy();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(readFileSync(join(f.output, 'new-runtime.dll'), 'utf8'), 'runtime:new-runtime.dll');
  assert.equal(readFileSync(join(f.output, 'locales/en-US.pak'), 'utf8'), 'locale');
  for (const name of ['dxil.dll', 'debug.pdb', 'static.lib']) assert.ok(!existsSync(join(f.output, name)));
  assert.equal(readFileSync(join(f.output, 'cef-runtime-files.txt'), 'utf8'), readFileSync(join(f.build, 'cef-runtime-files.txt'), 'utf8'));
});

test('older CEF SDKs keep libraries that were retired in later versions', { skip: process.platform !== 'win32' }, t => {
  const f = fixture(t, true);
  const result = f.copy();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  for (const name of legacyFiles) assert.equal(readFileSync(join(f.output, name), 'utf8'), `runtime:${name}`);
});

test('missing staged files and manifests fail before changing an existing destination', { skip: process.platform !== 'win32' }, t => {
  const f = fixture(t);
  mkdirSync(f.output);
  writeFileSync(join(f.output, 'previous'), 'preserve');
  rmSync(join(f.build, 'new-runtime.dll'));
  const missingFile = f.copy();
  assert.notEqual(missingFile.status, 0);
  assert.match(missingFile.stderr, /Missing staged CEF runtime file/);
  assert.equal(readFileSync(join(f.output, 'previous'), 'utf8'), 'preserve');
  assert.ok(!existsSync(join(f.output, 'libcef.dll')));
  rmSync(join(f.build, 'cef-runtime-files.txt'));
  const missingManifest = f.copy();
  assert.notEqual(missingManifest.status, 0);
  assert.match(missingManifest.stderr, /Missing CEF runtime manifest/);
});

test('unsafe paths, duplicates, executable/development entries and missing bootstrap dependencies are rejected', { skip: process.platform !== 'win32' }, t => {
  const f = fixture(t);
  const originalManifest = readFileSync(join(f.build, 'cef-runtime-files.txt'), 'utf8');
  for (const contents of ['../outside.dll\n', 'libcef.dll\nLIBCEF.dll\n', 'bootstrap.exe\n', 'debug.pdb\n', 'libcef.dll\nlocales\n']) {
    writeFileSync(join(f.build, 'cef-runtime-files.txt'), contents);
    const result = f.copy();
    assert.notEqual(result.status, 0, contents);
    assert.match(result.stderr, /Invalid or duplicate|Unexpected development|omits required/);
    assert.ok(!existsSync(f.output));
  }
  writeFileSync(join(f.build, 'cef-runtime-files.txt'), originalManifest);
  rmSync(join(f.build, 'libcef.dll'));
  mkdirSync(join(f.build, 'libcef.dll'));
  const wrongType = f.copy();
  assert.notEqual(wrongType.status, 0);
  assert.match(wrongType.stderr, /Missing staged CEF runtime file/);
  assert.ok(!existsSync(f.output));
});
