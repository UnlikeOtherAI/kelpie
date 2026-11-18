#!/usr/bin/env node
// Run before replacing a CEF 120 Linux installation. Only copied profiles are
// opened by either engine until cookie import and a real restart have passed.
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { chmod, cp, lstat, mkdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { call, lockProfile, startBrowser } from './profile-migration/linux-browser.mjs';
import { missingCookies, normalizeCookies, verifyCookies } from './profile-migration/cookies.mjs';

async function exists(path) {
  try { await lstat(path); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}
async function hash(path) {
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(path)) digest.update(chunk);
  return digest.digest('hex');
}
async function directory(path) {
  const info = await lstat(path);
  if (!info.isDirectory() || info.uid !== process.getuid()) throw new Error('Profile directories must belong to this user and cannot be symlinks');
}
async function copyProfile(from, to) {
  await cp(from, to, { recursive: true, force: false, errorOnExist: true, verbatimSymlinks: true,
    filter: async source => {
      if (['SingletonLock', 'SingletonCookie', 'SingletonSocket'].includes(source.split('/').at(-1))) return false;
      if ((await lstat(source)).isSymbolicLink()) throw new Error('Profile contains a symlink; refusing to open a copy that could write outside staging');
      return true;
    },
  });
  await chmod(to, 0o700);
}
async function seedSiteStorage(profile) {
  const cache = join(profile, 'cef-cache');
  const target = join(cache, 'Default');
  if (await exists(target)) return; // Existing modern site data always wins.
  await mkdir(cache, { recursive: true, mode: 0o700 });
  await mkdir(target, { mode: 0o700 });
  // Cookies use the API: Chromium 156 discards the CEF 120 database schema.
  for (const name of ['Local Storage', 'Session Storage', 'IndexedDB', 'Service Worker',
    'File System', 'WebStorage', 'databases', 'blob_storage', 'QuotaManager', 'QuotaManager-journal']) {
    if (await exists(join(cache, name))) await cp(join(cache, name), join(target, name), { recursive: true, verbatimSymlinks: true });
  }
}
async function readCookies(browser) {
  return normalizeCookies((await call(browser.ready, 'get-cookies', { all: true })).cookies);
}
async function withBrowser(binary, profile, action) {
  const browser = await startBrowser(binary, profile);
  try { return await action(browser); } finally { await browser.stop(); }
}

export async function migrate({ oldBinary, newBinary, profile, newSha256 }) {
  if (process.platform !== 'linux') throw new Error('This migration is for Linux CEF 120 profiles');
  if (![oldBinary, newBinary, profile].every(value => typeof value === 'string' && isAbsolute(value))) {
    throw new Error('Use absolute old-binary, new-binary and profile paths');
  }
  profile = resolve(profile);
  if (profile === '/') throw new Error('The filesystem root is not a browser profile');
  oldBinary = await realpath(oldBinary); newBinary = await realpath(newBinary);
  if (!/^[a-f0-9]{64}$/.test(newSha256 ?? '') || await hash(newBinary) !== newSha256) {
    throw new Error('New binary SHA-256 does not match the verified release');
  }
  const operation = `${profile}.chromium-upgrade`;
  const original = join(operation, 'original');
  const source = join(operation, 'source');
  const staged = join(operation, 'staged');
  const marker = '.kelpie-chromium-upgrade.json';
  // Recover an interrupted final rename automatically, before opening a browser.
  if (!await exists(profile) && await exists(original)) {
    await directory(operation); await directory(original);
    await rename(original, profile);
  }
  await directory(profile);
  const releaseLock = await lockProfile(profile);
  try {
    if (await exists(join(profile, marker))) return { status: 'already-migrated', backup: original };
    if (await exists(original)) throw new Error('An original backup already exists; refusing to overwrite it');
    if (await exists(operation)) await directory(operation);
    else await mkdir(operation, { mode: 0o700 });
    await chmod(operation, 0o700);
    for (const path of [source, staged]) await rm(path, { recursive: true, force: true });
    await copyProfile(profile, source);
    const legacy = await withBrowser(oldBinary, source, readCookies);
    if (legacy.some(cookie => cookie.expires === null)) {
      throw new Error('Transient cookies cannot be verified after restart; original profile is retained');
    }
    await copyProfile(profile, staged);
    await seedSiteStorage(staged);
    const expected = await withBrowser(newBinary, staged, async browser => {
      const current = await readCookies(browser);
      const missing = missingCookies(legacy, current);
      for (let offset = 0; offset < missing.length; offset += 500) {
        const batch = missing.slice(offset, offset + 500);
        const result = await call(browser.ready, 'set-cookies', { cookies: batch });
        if (result.set !== batch.length || result.failed?.length) {
          throw new Error('Cookie import was incomplete; original profile is retained');
        }
      }
      const expected = [...current, ...missing];
      verifyCookies(expected, await readCookies(browser));
      return expected;
    });
    await withBrowser(newBinary, staged, async browser => verifyCookies(expected, await readCookies(browser)));
    await writeFile(join(staged, marker), JSON.stringify({ version: 1, newSha256, cookieCount: expected.length }) + '\n', { mode: 0o600 });
    await rename(profile, original);
    try { await rename(staged, profile); }
    catch (error) { await rename(original, profile); throw error; }
    await rm(source, { recursive: true, force: true });
    return { status: 'migrated', cookies: expected.length, backup: original };
  } finally { await releaseLock(); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { values } = parseArgs({ options: {
      'old-binary': { type: 'string' }, 'new-binary': { type: 'string' },
      profile: { type: 'string' }, 'new-sha256': { type: 'string' },
    } });
    console.log(JSON.stringify(await migrate({ oldBinary: values['old-binary'], newBinary: values['new-binary'],
      profile: values.profile, newSha256: values['new-sha256'] })));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
