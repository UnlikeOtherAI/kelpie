import { test } from 'node:test';
import { deepStrictEqual } from 'node:assert';
import { classifyLint } from './lint-receipt.mjs';

test('emits only fixed paths and rules with line numbers', () => {
  const text = 'packages/shared lint: /private/candidate/packages/shared/src/browser-control/history.ts\npackages/shared lint:   42:8  error  private synthetic text  @typescript-eslint/no-unused-vars\n';
  deepStrictEqual(classifyLint(text), { version: 1, category: 'eslint-findings', findings: [
    { path: 'packages/shared/src/browser-control/history.ts', line: 42, rule: '@typescript-eslint/no-unused-vars' },
  ] });
});

test('does not disclose unknown paths, rules, or log content', () => {
  const text = '/private/other.ts\n  2:3  error  sensitive  no-undef\n/private/candidate/packages/shared/src/browser-control/history.ts\n  3:4  error  sensitive  unknown-secret\n';
  deepStrictEqual(classifyLint(text), { version: 1, category: 'unclassified', findings: [] });
});

test('caps input', () => {
  deepStrictEqual(classifyLint('x'.repeat(1_000_001)), { version: 1, category: 'log-too-large', findings: [] });
});
