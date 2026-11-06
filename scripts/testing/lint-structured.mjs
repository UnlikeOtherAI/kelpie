import { execFileSync, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { resolve, relative, sep } from 'node:path';
import { writeFile } from 'node:fs/promises';

// Only files in the frozen repository or the two verified additions may be named.
export function eligiblePath(root, file, tracked) {
  if (typeof file !== 'string') return null;
  const path = relative(root, resolve(file)).split(sep).join('/');
  return tracked.has(path) ? path : null;
}

export async function collectFindings(json, root, tracked, knownRules) {
  const records = JSON.parse(json);
  if (!Array.isArray(records) || records.length > 20000) throw new Error('invalid');
  const findings = [];
  let unclassified = 0;
  for (const record of records) {
    const path = eligiblePath(root, record.filePath, tracked);
    if (!path || !Array.isArray(record.messages)) { unclassified++; continue; }
    const rules = await knownRules(resolve(root, path));
    for (const item of record.messages) {
      if (findings.length >= 30) return { findings, truncated: true, unclassified };
      if (typeof item.ruleId === 'string' && rules.has(item.ruleId)
        && Number.isInteger(item.line) && item.line > 0 && item.line <= 1000000) {
        findings.push({ path, line: item.line, rule: item.ruleId });
      } else unclassified++;
    }
  }
  return { findings, truncated: false, unclassified };
}

async function main() {
  const root = process.cwd();
  const require = createRequire(resolve(root, 'package.json'));
  const { ESLint } = require('eslint');
  const tracked = new Set(execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8', maxBuffer: 4_000_000 }).split('\0').filter(Boolean));
  tracked.add('packages/shared/src/browser-control/history.ts');
  tracked.add('packages/shared/tests/playwright-history.test.ts');
  const stages = [
    { name: 'cli', cwd: 'packages/cli', args: ['src/', 'tests/'] },
    { name: 'shared', cwd: 'packages/shared', args: ['src/', 'tests/'] },
    { name: 'capture', cwd: '.', args: ['--config', 'scripts/testing/capture-eslint.config.mjs', 'tests/capture', 'tests/linux', 'tests/macos', 'tests/windows'] },
  ];
  const results = [];
  for (const stage of stages) {
    const cwd = resolve(root, stage.cwd);
    const run = spawnSync('pnpm', ['exec', 'eslint', ...stage.args, '--format', 'json'], { cwd, encoding: 'utf8', timeout: 180000, maxBuffer: 4_000_000 });
    const result = { stage: stage.name, status: run.status === 0 ? 'pass' : run.status === 1 ? 'failed' : 'unavailable', findings: [], truncated: false };
    if (run.status === 1) {
      try {
        const eslint = new ESLint(stage.name === 'capture' ? { cwd, overrideConfigFile: resolve(root, 'scripts/testing/capture-eslint.config.mjs') } : { cwd });
        const classified = await collectFindings(run.stdout, root, tracked, async file => new Set(Object.keys((await eslint.calculateConfigForFile(file))?.rules ?? {})));
        Object.assign(result, classified);
      } catch { result.status = 'unclassified'; }
    }
    results.push(result);
  }
  await writeFile(process.argv[2], JSON.stringify({ version: 1, stages: results }) + '\n', { flag: 'wx', mode: 0o600 });
}

if (process.argv[1]?.endsWith('lint-structured.mjs')) main().catch(() => { process.stderr.write('LINT_DIAGNOSTIC_FAILED\n'); process.exitCode = 1; });
