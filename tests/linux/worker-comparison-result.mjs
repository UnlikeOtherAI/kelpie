import assert from "node:assert/strict";

// No ratio is emitted. Only comparable, individually correct receipts qualify.
export function compareWorkerReceipts(a,b){
 assert.equal(a?.version,1);assert.equal(b?.version,1);
 assert.deepEqual([a.backend,b.backend].sort(),["lightpanda","playwright"]);
 for(const key of ["source","comparisonId","hostBinding","nodeVersion","architecture","kernelRelease",
  "fixtureSHA256","cliVersion","cliBundleSHA256","sharedBundleSHA256"])
  assert.ok(typeof a[key]==="string"&&a[key].length>0&&a[key]===b[key],"COMPARISON_IDENTITY_MISMATCH");
 assert.match(a.source,/^[a-f0-9]{40}$/);
 for(const key of ["comparisonId","hostBinding","fixtureSHA256","cliBundleSHA256","sharedBundleSHA256"])
  assert.match(a[key],/^[a-f0-9]{64}$/);
 const lp=a.backend==="lightpanda"?a:b,chromium=a.backend==="playwright"?a:b;
 assert.equal(lp.engineVersion,"1.0.2");
 assert.equal(lp.engineSHA256,"ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e");
 assert.match(chromium.engineVersion,/\b151\.0\.7922\.34\b/);
 assert.match(chromium.engineSHA256??"",/^[a-f0-9]{64}$/);
 assert.match(chromium.archiveSHA256??"",/^[a-f0-9]{64}$/);
 assert.deepEqual(a.boundary,b.boundary,"COMPARISON_BOUNDARY_MISMATCH");
 assert.ok(Number.isSafeInteger(a.uid)&&a.uid>0&&a.uid===b.uid,"COMPARISON_USER_MISMATCH");
 for(const r of [a,b])assert.deepEqual(r.networkProbe,{local:"connected",nonlocal:"denied"});
 assert.equal(a.eligibleForComparison,true);assert.equal(b.eligibleForComparison,true);
 assert.equal(a.forcedCleanup,false);assert.equal(b.forcedCleanup,false);
 assert.equal(a.engineExited,true);assert.equal(b.engineExited,true);
 assert.ok(a.checks.length>0&&a.checks.every(c=>c.passed)&&b.checks.every(c=>c.passed));
 assert.deepEqual(a.checks.map(c=>c.name),b.checks.map(c=>c.name),"COMPARISON_CORPUS_MISMATCH");
 for(const r of [a,b]){
  assert.ok(Number.isFinite(r.startupMs)&&r.startupMs>=0&&r.warm.length===5);
  assert.ok(r.rss.samples>0&&r.rss.readFailures===0);
 }
 assert.deepEqual([a.coldCorpus,...a.warm].map(x=>x.toolCalls),
  [b.coldCorpus,...b.warm].map(x=>x.toolCalls),"COMPARISON_CALL_COUNT_MISMATCH");
 return {identityAndCorpusMatched:true,requiresIndependentNetworkBoundaryVerification:true,
  scope:"sampled unit costs; no UI or native parity",
  lightpanda:a.backend==="lightpanda"?a:b,chromium:a.backend==="playwright"?a:b};
}
