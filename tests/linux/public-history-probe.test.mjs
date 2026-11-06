import { test } from 'node:test';
import { strictEqual } from 'node:assert';
import { createHistoryProbe } from './worker-comparison-history-probe.mjs';

test('forward pageshow and same-document events require prior anchors', () => {
  const p = createHistoryProbe(); p.record('r0'); p.record('n0');
  let mark = p.mark(); p.record('n1');
  strictEqual(p.result(mark, 'next').status, 'restored-from-bfcache');
  mark = p.mark(); p.record('h1');
  strictEqual(p.hashResult(mark, 'h1', false).status, 'observed');
  strictEqual(p.hashResult(mark, 'h1').status, 'insufficient');
  p.record('h2'); mark = p.mark(); p.record('h1');
  strictEqual(p.hashResult(mark, 'h1').status, 'observed');
  p.record('h1'); strictEqual(p.hashResult(mark, 'h1').status, 'insufficient');
});
