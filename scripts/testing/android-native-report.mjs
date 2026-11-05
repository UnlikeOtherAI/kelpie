import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

export function summarize(root) {
  const report = {
    sourceRevision: readFileSync(join(root, 'source-revision.txt'), 'utf8').trim(),
    physicalDevice: false, runtimeMode: 'windowed', profiles: [],
  };
  for (const profile of ['phone', 'tablet']) {
    const folder = join(root, profile);
    const read = (name) => existsSync(join(folder, name)) ? readFileSync(join(folder, name), 'utf8').trim() : '';
    const text = read('instrumentation.log');
    const match = /^OK \((\d+) tests?\)/m.exec(text);
    const failed = /FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed/.test(text);
    const exports = [];
    function collect(path) {
      if (!existsSync(path)) return;
      if (statSync(path).isDirectory()) {
        for (const name of readdirSync(path).sort()) collect(join(path, name));
      } else {
        const bytes = readFileSync(path);
        exports.push({ path: relative(root, path).replaceAll('\\', '/'), bytes: bytes.length,
          sha256: createHash('sha256').update(bytes).digest('hex') });
      }
    }
    for (const name of ['script-acceptance', 'script-codec-acceptance']) collect(join(folder, name));
    let cli = null;
    try { cli = JSON.parse(read('cli-report.json')); } catch { /* Missing/invalid report fails closed. */ }
    const cliPassed = cli?.success === true && read('cli-exit.txt') === '0' && /^OK \(1 test\)/m.test(read('cli-instrumentation.log'));
    report.profiles.push({ deviceClass: profile, cliPassed, passed: Boolean(match) && !failed && read('instrumentation-exit.txt') === '0' && cliPassed,
      tests: match ? Number(match[1]) : null, exports, blocker: read('blocker.txt') || null });
  }
  return report;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  writeFileSync(join(process.argv[2], 'report.json'), JSON.stringify(summarize(process.argv[2]), null, 2) + '\n');
}