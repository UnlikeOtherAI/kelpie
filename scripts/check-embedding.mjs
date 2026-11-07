import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = name => readFile(resolve(root, name), 'utf8');
const sourceFiles = async directory => {
  const entries = await readdir(resolve(root, directory), { withFileTypes: true });
  const nested = await Promise.all(entries.filter(entry => !['Frameworks', 'vendor', '.build'].includes(entry.name)).map(entry => entry.isDirectory()
    ? sourceFiles(directory + '/' + entry.name) : directory + '/' + entry.name));
  return nested.flat();
};

for (const file of await sourceFiles('core/apple')) {
  if (!file.endsWith('.swift')) continue;
  const source = await read(file);
  assert(!source.includes('@main'), file + ' must not own the app entry point');
  assert(!source.includes('KelpieApp.'), file + ' depends on the standalone app');
}
for (const file of await sourceFiles('core/android/src/main/java')) {
  const source = await read(file);
  assert(!source.includes('import com.kelpie.browser.MainActivity'), file + ' depends on the standalone activity');
  assert(!source.includes('import com.kelpie.browser.KelpieApp'), file + ' depends on the standalone application');
}
for (const platform of ['ios', 'macos']) {
  const app = await read('apps/' + platform + '/Kelpie/KelpieApp.swift');
  assert(app.split('\n').length < 40, platform + ' app must remain a thin host');
  assert(app.includes('import KelpieBrowser'));
}
assert((await read('apps/windows/CMakeLists.txt')).includes('Kelpie::Browser'));
assert(!(await read('apps/linux/CMakeLists.txt')).includes('core/apple'));
console.log('Embeddable browser ownership checks passed.');
