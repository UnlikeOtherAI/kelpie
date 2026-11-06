import {constants} from 'node:fs';
import {copyFile, lstat, mkdir, realpath} from 'node:fs/promises';
import {dirname, join, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';

const setup = ['playwright-archive-sha256.txt', 'google-archive-sha256.txt', 'playwright-source.txt',
 'google-source.txt', 'provenance-limits.txt', 'chromium-binary-sha256.txt', 'chromium-version.txt',
 'source.txt', 'lightpanda-sha256.txt'];
const armFiles = ['report.json', 'retirement.json', 'policy-observed.json', 'policy-verified.json',
 'namespace-verified.json', 'namespace-query-status.json', 'outside-probe.json', 'network-observation.json',
 'host-sandbox-result.json', 'bpf-status.txt'];
export const allowedEvidence = Object.freeze([
 ...setup.map(name => `worker-ab-setup/${name}`), 'worker-ab-evidence/comparison.json',
 ...['lightpanda', 'playwright', 'probe', 'sandbox', 'eof'].flatMap(arm => armFiles.map(name => `worker-ab-evidence/${arm}/${name}`)),
]);

export async function copyReviewedEvidence(source, destination) {
 const root = await realpath(source), target = resolve(destination);
 await mkdir(target, {recursive: false, mode: 0o700});
 let copied = 0;
 for (const name of allowedEvidence) {
  const file = join(root, name);
  let info;
  try { info = await lstat(file); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
  if (!info.isFile() || info.size > 1_000_000) throw new Error('EVIDENCE_INVALID');
  const actual = await realpath(file);
  if (!actual.startsWith(root + sep)) throw new Error('EVIDENCE_INVALID');
  const out = join(target, name);
  await mkdir(dirname(out), {recursive: true, mode: 0o700});
  await copyFile(actual, out, constants.COPYFILE_EXCL);
  copied++;
 }
 return copied;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
 try { await copyReviewedEvidence(process.argv[2], process.argv[3]); }
 catch { process.stderr.write('EVIDENCE_STAGING_FAILED\n'); process.exitCode = 1; }
}
