import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const marker = '<!-- kelpie-update: ';
export const targets = ['macos-arm64', 'macos-x64', 'windows-x64',
  'linux-x64-appimage', 'linux-x64-deb', 'linux-x64-rpm', 'linux-x64-tar', 'ios', 'android'];

export function updateNotes(release, { target, version, asset, storeURL }) {
  if (!targets.includes(target) || !/^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(version ?? '')) {
    throw new Error('A supported target and numeric component version are required.');
  }
  if (release.draft || release.prerelease) throw new Error('Only a published stable release can advertise an update.');
  let url, sha256;
  if (storeURL) {
    const iosStore = /^https:\/\/apps\.apple\.com\/([a-z]{2}\/)?app\/([a-zA-Z0-9-]+\/)?id[0-9]+$/;
    if (!((target === 'ios' && iosStore.test(storeURL)) ||
      (target === 'android' && storeURL === 'https://play.google.com/store/apps/details?id=com.kelpie.browser'))) {
      throw new Error('Store links are supported only for the mobile application.');
    }
    url = storeURL;
  } else {
    if (target === 'ios') throw new Error('iOS updates require a published App Store update page. Simulator ZIPs and raw IPAs cannot be installed from this prompt.');
    const uploaded = release.assets?.find(item => item.name === asset && item.state === 'uploaded');
    if (!uploaded || !/^sha256:[a-f0-9]{64}$/.test(uploaded.digest ?? '')) {
      throw new Error('The complete uploaded asset and its GitHub SHA-256 digest are required.');
    }
    url = uploaded.browser_download_url;
    const prefix = 'https://github.com/UnlikeOtherAI/kelpie/releases/download/';
    if (!url?.startsWith(prefix) || /[\s\\?#%]|\.\./.test(url)) throw new Error('Unexpected release asset URL.');
    const extension = target === 'android' ? '.apk' :
      target.endsWith('-appimage') ? '.AppImage' : target.endsWith('-deb') ? '.deb' :
        target.endsWith('-rpm') ? '.rpm' : target.endsWith('-tar') ? '.tar.gz' : '.zip';
    if (!uploaded.name.endsWith(extension)) throw new Error(`Expected an installable ${extension} asset for ${target}.`);
    sha256 = uploaded.digest.slice(7);
  }
  const item = { target, version, url, ...(sha256 ? { sha256 } : {}) };
  // Replace only this target's metadata, preserving component-selection headers,
  // release notes and other platforms' independently published updates.
  const body = (release.body ?? '').replace(/<!-- kelpie-update: ([^\n]*?) -->\r?\n?/g, (line, json) => {
    try { return JSON.parse(json).target === target ? '' : line; } catch { return line; }
  }).trimEnd();
  return `${body}\n\n${marker}${JSON.stringify(item)} -->\n`;
}

function main() {
  const options = {};
  for (let i = 2; i < process.argv.length; i += 2) {
    const key = process.argv[i];
    if (!['--tag', '--target', '--version', '--asset', '--store-url'].includes(key) || !process.argv[i + 1]) {
      throw new Error('Usage: publish-app-update.mjs --tag TAG --target TARGET --version VERSION (--asset NAME | --store-url URL)');
    }
    options[key.slice(2)] = process.argv[i + 1];
  }
  if (!options.tag || !options.target || !options.version || Boolean(options.asset) === Boolean(options['store-url'])) {
    throw new Error('Specify tag, target, version and exactly one asset or store URL.');
  }
  const api = (...args) => execFileSync('gh', ['api', ...args], { encoding: 'utf8' });
  const release = JSON.parse(api(`repos/UnlikeOtherAI/kelpie/releases/tags/${encodeURIComponent(options.tag)}`));
  const body = updateNotes(release, { ...options, storeURL: options['store-url'] });
  execFileSync('gh', ['api', `repos/UnlikeOtherAI/kelpie/releases/${release.id}`, '--method', 'PATCH', '--input', '-'], {
    input: JSON.stringify({ body }), stdio: ['pipe', 'ignore', 'inherit'],
  });
  console.log(`Published ${options.target} ${options.version} update metadata on ${options.tag}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
