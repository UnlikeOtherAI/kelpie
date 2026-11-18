import { createHash } from 'node:crypto';

export const CEF_INDEX = 'https://cef-builds.spotifycdn.com/index.json';
export const PLATFORMS = ['macosarm64', 'windows64', 'linux64'];
const chromePlatforms = { macosarm64: 'mac_arm64', windows64: 'win64', linux64: 'linux' };
const cefPattern = /^(\d+\.\d+\.\d+)\+g[0-9a-f]+\+chromium-(\d+\.\d+\.\d+\.\d+)$/;

export function chromiumVersion(cef) {
  const match = cefPattern.exec(cef);
  if (!match) throw new Error(`Invalid CEF version: ${cef}`);
  return match[2];
}

export function compareVersions(a, b) {
  if (![a, b].every(v => /^\d+(\.\d+){2,3}$/.test(v))) throw new Error('Invalid numeric version');
  const left = a.split('.').map(Number);
  const right = b.split('.').map(Number);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const difference = (left[i] ?? 0) - (right[i] ?? 0);
    if (difference) return Math.sign(difference);
  }
  return 0;
}

export function compareCef(a, b) {
  return compareVersions(chromiumVersion(a), chromiumVersion(b)) ||
    compareVersions(a.split('+')[0], b.split('+')[0]);
}

export function latestStable(index, platform) {
  const versions = index[platform]?.versions;
  if (!Array.isArray(versions)) throw new Error(`Missing CEF platform: ${platform}`);
  // The index retains pre-2019 CEF 3.x archives, before Chromium was part of
  // the CEF version string. They cannot upgrade any supported Kelpie pin.
  const candidates = versions.filter(v => v.channel === 'stable' &&
    !/^3\.\d+\.\d+\.g[0-9a-f]+$/.test(v.cef_version)).map(v => {
    if (chromiumVersion(v.cef_version) !== v.chromium_version) throw new Error('CEF/Chromium version mismatch');
    const name = `cef_binary_${v.cef_version}_${platform}_minimal.tar.bz2`;
    const file = v.files?.find(f => f.type === 'minimal' && f.name === name);
    if (!file) return null;
    if (!/^[a-f0-9]{40}$/i.test(file.sha1) || !Number.isSafeInteger(file.size) ||
        file.size <= 0 || file.size > 2_000_000_000 || !Number.isFinite(Date.parse(file.last_modified))) {
      throw new Error(`Invalid CEF archive metadata: ${name}`);
    }
    return { platform, cef: v.cef_version, chromium: v.chromium_version,
      url: `https://cef-builds.spotifycdn.com/${name}`, sha1: file.sha1.toLowerCase(),
      size: file.size, publishedAt: file.last_modified };
  }).filter(Boolean);
  candidates.sort((a, b) => compareCef(b.cef, a.cef));
  if (!candidates.length) throw new Error(`No stable minimal CEF archive for ${platform}`);
  return candidates[0];
}

export async function fetchJson(url, fetcher = fetch) {
  const response = await fetcher(url, { signal: AbortSignal.timeout(120_000), redirect: 'error' });
  if (!response.ok) throw new Error(`Upstream HTTP ${response.status}: ${url}`);
  return response.json();
}

export async function chromeStable(platform, fetcher = fetch) {
  const url = `https://versionhistory.googleapis.com/v1/chrome/platforms/${chromePlatforms[platform]}/channels/stable/versions?order_by=version%20desc&page_size=1`;
  const data = await fetchJson(url, fetcher);
  const version = data.versions?.[0]?.version;
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(version ?? '')) throw new Error(`Missing Chrome stable version: ${platform}`);
  return { version, url };
}

// Stream the archive without executing or extracting upstream content. SHA-1 is
// the CEF index's published checksum; SHA-256 becomes the candidate's evidence.
export async function verifyArchive(candidate, fetcher = fetch) {
  if (!candidate.url.startsWith('https://cef-builds.spotifycdn.com/cef_binary_')) throw new Error('Unexpected archive host');
  const response = await fetcher(candidate.url, { signal: AbortSignal.timeout(600_000), redirect: 'error' });
  if (!response.ok || !response.body) throw new Error(`Archive HTTP ${response.status}`);
  const sha1 = createHash('sha1');
  const sha256 = createHash('sha256');
  let bytes = 0;
  for await (const chunk of response.body) {
    bytes += chunk.length;
    if (bytes > candidate.size) throw new Error('CEF archive exceeds declared size');
    sha1.update(chunk);
    sha256.update(chunk);
  }
  if (bytes !== candidate.size || sha1.digest('hex') !== candidate.sha1) throw new Error('CEF archive checksum/size mismatch');
  return sha256.digest('hex');
}
