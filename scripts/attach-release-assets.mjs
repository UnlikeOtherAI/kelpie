import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readdir } from 'node:fs/promises';
import { basename, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export async function fileDigest(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return `sha256:${hash.digest('hex')}`;
}

async function artifactFiles(root) {
  const files = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Release artifacts must not contain symlinks: ${path}`);
    if (entry.isDirectory()) files.push(...await artifactFiles(path));
    else if (/\.(tar\.gz|deb|rpm|AppImage|apk|aab|tgz)$/.test(entry.name) || /^checksums-.+\.txt$/.test(entry.name)) files.push(path);
  }
  return files.sort();
}

export async function attachReleaseAssets(tag, root, run = args => execFileSync('gh', args, { encoding: 'utf8' })) {
  const files = await artifactFiles(root);
  if (!files.length) throw new Error('No completed release artifacts found.');
  const names = files.map(file => basename(file));
  if (new Set(names).size !== names.length) throw new Error('Release artifact names must be unique across components.');
  const getRelease = () => JSON.parse(run(['api', `repos/UnlikeOtherAI/kelpie/releases/tags/${encodeURIComponent(tag)}`]));
  const release = getRelease();
  if (release.draft || release.prerelease || release.tag_name !== tag) throw new Error('A matching published stable release is required.');
  const planned = [];
  for (const file of files) {
    const name = basename(file), digest = await fileDigest(file);
    const existing = release.assets.find(asset => asset.name === name);
    if (existing && (existing.state !== 'uploaded' || existing.digest !== digest)) throw new Error(`Refusing to replace a different or incomplete release asset: ${name}`);
    planned.push({ file, name, digest, existing });
  }
  let uploaded = 0;
  for (const { file, existing } of planned) {
    if (!existing) {
      // Upload only: do not rewrite tag_name, target_commitish or release notes.
      run(['release', 'upload', tag, file]);
      uploaded++;
    }
  }
  const completed = getRelease();
  for (const { name, digest } of planned) {
    const asset = completed.assets.find(item => item.name === name);
    if (asset?.state !== 'uploaded' || asset.digest !== digest) throw new Error(`Uploaded asset digest was not verified: ${name}`);
  }
  return { uploaded, verified: files.length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2] || !process.argv[3]) throw new Error('Usage: attach-release-assets.mjs TAG ARTIFACT_DIRECTORY');
  console.log(await attachReleaseAssets(process.argv[2], process.argv[3]));
}
