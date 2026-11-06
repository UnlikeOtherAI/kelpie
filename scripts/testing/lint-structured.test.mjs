import { test } from 'node:test';
import { deepStrictEqual, strictEqual } from 'node:assert';
import { resolve } from 'node:path';
import { collectFindings, eligiblePath } from './lint-structured.mjs';

test('accepts only tracked paths and actual configured rules', async () => {
  const root = resolve('candidate');
  const tracked = new Set(['packages/shared/src/a.ts']);
  const json = JSON.stringify([{ filePath: resolve(root, 'packages/shared/src/a.ts'), messages: [
    { line: 3, ruleId: 'known', message: 'private' }, { line: 4, ruleId: 'secret', message: 'private' },
  ] }, { filePath: resolve(root, '../private.ts'), messages: [{ line: 1, ruleId: 'known' }] }]);
  deepStrictEqual(await collectFindings(json, root, tracked, async () => new Set(['known'])), {
    findings: [{ path: 'packages/shared/src/a.ts', line: 3, rule: 'known' }], truncated: false, unclassified: 2,
  });
  strictEqual(eligiblePath(root, resolve(root, '../private.ts'), tracked), null);
});

test('bounds findings without copying messages', async () => {
  const root = resolve('candidate');
  const path = 'packages/shared/src/a.ts';
  const json = JSON.stringify([{ filePath: resolve(root, path), messages: Array.from({ length: 31 }, () => ({ line: 5, ruleId: 'known', message: 'private' })) }]);
  const result = await collectFindings(json, root, new Set([path]), async () => new Set(['known']));
  strictEqual(result.findings.length, 30);
  strictEqual(result.truncated, true);
});
