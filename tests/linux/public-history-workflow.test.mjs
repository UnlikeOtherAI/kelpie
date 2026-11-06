import { test } from 'node:test';
import { strictEqual, ok } from 'node:assert';
import { readFile } from 'node:fs/promises';

test('public history is an opt-in default-BFCache Chromium diagnostic', async () => {
  const lint = await readFile(new URL('../../.github/workflows/lint.yml', import.meta.url), 'utf8');
  const workflow = await readFile(new URL('../../.github/workflows/worker-comparison.yml', import.meta.url), 'utf8');
  const hosted = await readFile(new URL('../../scripts/testing/run-worker-comparison-hosted.sh', import.meta.url), 'utf8');
  const runner = await readFile(new URL('./worker-comparison.mjs', import.meta.url), 'utf8');
  ok(lint.includes('- public-history-2204'));
  ok(lint.includes("public_history: ${{ inputs.worker_comparison_mode == 'public-history-2204' }}"));
  ok(workflow.includes('"$DIAGNOSTIC_ONLY" == true && "$BFCACHE_OFF" == false'));
  ok(hosted.includes('--setenv="KELPIE_AB_PUBLIC_HISTORY=$public_history"'));
  ok(hosted.includes('"$diagnostic_only" == true && "$bfcache_off" == false'));
  ok(runner.includes('!publicHistory||(diagnostic&&!bfcacheOff)'));
  ok(runner.includes('assert.ok(!diagnostic||backend==="playwright"'));
  ok(runner.includes('await bounded(client.callTool({name,arguments:arguments_}),5000)'));
  ok(runner.includes('report.publicHistory=createPublicHistoryReport()'));
  ok(runner.includes('report.cleanup.session.tabClose=error===diagnosticTimeout?"timeout":"transport-error"'));
  ok(runner.includes('report.cleanup.session.sessionClose="error"'));
  strictEqual((lint.match(/^          - public-history-2204$/gm) ?? []).length, 1);
});

test('no-history calls follow sandbox proof and require a single preflight fixture', async()=>{
 const runner=await readFile(new URL('./worker-comparison.mjs',import.meta.url),'utf8');
 const proof=runner.indexOf('assert.ok(report.sessionSandboxEvidence,"CHROMIUM_SANDBOX_NOT_PROVEN")');
 const check=runner.indexOf('await publicHistoryDiagnostic(');
 ok(proof>=0&&check>proof);
 ok(runner.includes('preflightRequests===1?noHistory.result():{status:"insufficient"}'));
});
