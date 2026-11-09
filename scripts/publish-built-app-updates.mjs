import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { taggedComponentVersion } from './publish-app-update.mjs';

// Run after attaching and verifying the release artifacts, never at release creation.
const tag = process.argv[2];
if (!tag) throw new Error('Usage: publish-built-app-updates.mjs TAG');
const release = JSON.parse(execFileSync('gh', ['api',
  `repos/UnlikeOtherAI/kelpie/releases/tags/${encodeURIComponent(tag)}`], { encoding: 'utf8' }));
const api = path => execFileSync('gh', ['api', path], { encoding: 'utf8' });
const linux = taggedComponentVersion(api, tag, 'linux-x64-tar');
const android = taggedComponentVersion(api, tag, 'android');
const jobs = [
  ['linux-x64-appimage', linux, name => name.endsWith('.AppImage')],
  ['linux-x64-deb', linux, name => name.endsWith('.deb')],
  ['linux-x64-rpm', linux, name => name.endsWith('.rpm')],
  ['linux-x64-tar', linux, name => name.endsWith('-ubuntu-22.04-x86_64.tar.gz')],
  ['android', android, name => name.endsWith('.apk')],
];
for (const [target, version, matches] of jobs) {
  const assets = release.assets.filter(item => matches(item.name));
  if (!assets.length) continue;
  if (assets.length !== 1) throw new Error(`Ambiguous update asset for ${target}`);
  execFileSync(process.execPath, [fileURLToPath(new URL('./publish-app-update.mjs', import.meta.url)),
    '--tag', tag, '--target', target, '--version', version, '--asset', assets[0].name], { stdio: 'inherit' });
}
