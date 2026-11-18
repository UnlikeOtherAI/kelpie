import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { compareCef, chromiumVersion } from './upstream.mjs';

export const FILES = ['scripts/download-cef.sh', 'scripts/download-cef-windows.ps1',
  'scripts/package-windows.ps1', 'scripts/test-cef-upstream.sh'];

export function readSources(root = '.', revision) {
  return Object.fromEntries(FILES.map(path => [path, revision
    ? execFileSync('git', ['show', `${revision}:${path}`], { cwd: root, encoding: 'utf8' })
    : readFileSync(`${root}/${path}`, 'utf8')]));
}

function exactlyOne(text, pattern, label) {
  const matches = [...text.matchAll(new RegExp(pattern, 'g'))];
  if (matches.length !== 1) throw new Error(`Expected one ${label}; found ${matches.length}`);
  return matches[0][1];
}

export function readPins(sources) {
  const shell = sources[FILES[0]];
  const pins = {
    macosarm64: exactlyOne(shell, 'install_macos_arm64\\(\\) \\{\\s+local cef_version="([^"]+)"', 'Mac pin'),
    linux64: exactlyOne(shell, 'install_linux_x64\\(\\) \\{\\s+local cef_version="([^"]+)"', 'Linux pin'),
    windows64: exactlyOne(sources[FILES[1]], '\\$version = "([^"]+)"', 'Windows pin'),
  };
  Object.values(pins).forEach(chromiumVersion);
  const packageVersion = exactlyOne(sources[FILES[2]], '\\$cefVersion = "([^"]+)"', 'Windows package pin');
  const packageRoot = exactlyOne(sources[FILES[2]], 'cef_binary_([^"\\s]+)_windows64_minimal', 'Windows package path');
  const testVersion = exactlyOne(sources[FILES[3]], 'CEF_VERSION="\\$\\{1:-([^}]+)\\}"', 'Mac test pin');
  if (packageVersion !== pins.windows64 || packageRoot !== pins.windows64 || testVersion !== pins.macosarm64) {
    throw new Error('CEF pins disagree with their package/test consumers');
  }
  return pins;
}

export function planUpdates(pins, candidates) {
  return candidates.map(candidate => ({ ...candidate, current: pins[candidate.platform],
    update: compareCef(candidate.cef, pins[candidate.platform]) > 0 }));
}

function replaceExactly(text, before, after, count = 1) {
  if (text.split(before).length - 1 !== count) throw new Error(`Pin layout changed: ${before}`);
  return text.split(before).join(after);
}

export function updateSources(sources, plan) {
  const updated = { ...sources };
  for (const candidate of plan.filter(item => item.update)) {
    if (!/^[a-f0-9]{64}$/i.test(candidate.sha256 ?? '')) throw new Error('Missing verified archive SHA-256');
    if (candidate.platform === 'windows64') {
      updated[FILES[1]] = replaceExactly(updated[FILES[1]], candidate.current, candidate.cef);
      for (const [key, digest, length] of [['expectedSha1', candidate.sha1, 40], ['expectedSha256', candidate.sha256, 64]]) {
        const old = exactlyOne(updated[FILES[1]], `\\$${key} = "([A-Fa-f0-9]{${length}})"`, key);
        updated[FILES[1]] = replaceExactly(updated[FILES[1]], old, digest.toUpperCase());
      }
      updated[FILES[2]] = replaceExactly(updated[FILES[2]], candidate.current, candidate.cef, 2);
    } else {
      const fn = candidate.platform === 'macosarm64' ? 'install_macos_arm64' : 'install_linux_x64';
      // Anchor to the function; Mac and Linux can legitimately share a pin.
      const anchor = `${fn}() {`;
      const start = updated[FILES[0]].indexOf(anchor);
      if (start < 0 || updated[FILES[0]].indexOf(anchor, start + 1) >= 0) throw new Error('Ambiguous platform function');
      const end = updated[FILES[0]].indexOf('\n}', start);
      if (end < 0) throw new Error('Missing platform function terminator');
      const section = updated[FILES[0]].slice(start, end);
      updated[FILES[0]] = updated[FILES[0]].slice(0, start) +
        replaceExactly(section, candidate.current, candidate.cef) + updated[FILES[0]].slice(end);
      if (candidate.platform === 'macosarm64') updated[FILES[3]] = replaceExactly(updated[FILES[3]], candidate.current, candidate.cef);
    }
  }
  readPins(updated);
  return Object.fromEntries(Object.entries(updated).filter(([path, text]) => text !== sources[path]));
}
