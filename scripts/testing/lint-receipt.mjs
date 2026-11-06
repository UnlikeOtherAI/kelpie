import { readFile, stat, writeFile } from 'node:fs/promises';

const paths = new Set([
  'packages/shared/src/browser-control/history.ts',
  'packages/shared/src/browser-control/managed-session.ts',
  'packages/shared/src/browser-control/playwright.ts',
  'packages/shared/tests/playwright-history.test.ts',
]);
const rules = new Set([
  '@typescript-eslint/no-unnecessary-condition', '@typescript-eslint/no-unsafe-assignment',
  '@typescript-eslint/no-unsafe-call', '@typescript-eslint/no-unsafe-return',
  '@typescript-eslint/no-unused-vars', '@typescript-eslint/no-floating-promises',
  '@typescript-eslint/require-await', '@typescript-eslint/return-await',
  '@typescript-eslint/strict-boolean-expressions', '@typescript-eslint/unbound-method',
  '@typescript-eslint/no-confusing-void-expression', '@typescript-eslint/no-unnecessary-type-assertion',
  '@typescript-eslint/no-non-null-assertion', '@typescript-eslint/consistent-return',
  'consistent-return', 'no-undef', 'no-unused-vars', 'prefer-const',
]);

export function classifyLint(text) {
  if (Buffer.byteLength(text) > 1_000_000) return { version: 1, category: 'log-too-large', findings: [] };
  const findings = [];
  let current;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/^packages\/shared lint: /, '');
    const path = line.replaceAll('\\', '/').trim();
    if (path.startsWith('/')) {
      current = [...paths].find(p => path.endsWith('/' + p));
      continue;
    }
    const match = line.match(/^\s*(\d{1,6}):\d{1,6}\s+(?:error|warning)\s+.*\s(@?[a-z0-9][a-z0-9@/_-]{0,100})\s*$/i);
    if (current && match && rules.has(match[2]) && findings.length < 30) findings.push({ path: current, line: Number(match[1]), rule: match[2] });
  }
  return { version: 1, category: findings.length ? 'eslint-findings' : 'unclassified', findings };
}

if (process.argv[1]?.endsWith('lint-receipt.mjs')) {
  try {
    const info = await stat(process.argv[2]);
    const result = info.size > 1_000_000
      ? { version: 1, category: 'log-too-large', findings: [] }
      : classifyLint(await readFile(process.argv[2], 'utf8'));
    await writeFile(process.argv[3], JSON.stringify(result) + '\n', { flag: 'wx', mode: 0o600 });
  } catch {
    process.stderr.write('LINT_RECEIPT_FAILED\n');
    process.exitCode = 1;
  }
}
