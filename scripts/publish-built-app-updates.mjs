import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { taggedComponentVersion } from './publish-app-update.mjs';

// Run after attaching and verifying the release artifacts, never at release creation.
export function publishBuiltAppUpdates(tag, run = (file, args) => execFileSync(file, args, { encoding: 'utf8' })) {
  const api = path => run('gh', ['api', path]);
  const release = JSON.parse(api(`repos/UnlikeOtherAI/kelpie/releases/tags/${encodeURIComponent(tag)}`));
  if (release.draft || release.tag_name !== tag) throw new Error('A matching published release is required.');
  // Read live state: a release may have been held after its build started.
  if (release.prerelease) return { stable: false, advertised: 0 };
  const jobs = [
    ['linux-x64-appimage', name => name.endsWith('.AppImage')],
    ['linux-x64-deb', name => name.endsWith('.deb')],
    ['linux-x64-rpm', name => name.endsWith('.rpm')],
    ['linux-x64-tar', name => name.endsWith('-ubuntu-22.04-x86_64.tar.gz')],
    ['android', name => name.endsWith('.apk')],
  ];
  let advertised = 0;
  for (const [target, matches] of jobs) {
    const assets = release.assets.filter(item => matches(item.name));
    if (!assets.length) continue;
    if (assets.length !== 1) throw new Error(`Ambiguous update asset for ${target}`);
    const version = taggedComponentVersion(api, tag, target);
    run(process.execPath, [fileURLToPath(new URL('./publish-app-update.mjs', import.meta.url)),
      '--tag', tag, '--target', target, '--version', version, '--asset', assets[0].name]);
    advertised++;
  }
  return { stable: true, advertised };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) throw new Error('Usage: publish-built-app-updates.mjs TAG');
  const result = publishBuiltAppUpdates(process.argv[2]);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `stable=${result.stable}\n`);
  console.log(result);
}
