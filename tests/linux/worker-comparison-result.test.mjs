import {test} from "node:test";
import assert from "node:assert/strict";
import {compareWorkerReceipts} from "./worker-comparison-result.mjs";
function receipt(backend){
 return {version:1,backend,source:"a".repeat(40),comparisonId:"b".repeat(64),hostBinding:"c".repeat(64),nodeVersion:"node",
  architecture:"x64",kernelRelease:"linux",fixtureSHA256:"d".repeat(64),cliVersion:"1",cliBundleSHA256:"e".repeat(64),
  sharedBundleSHA256:"f".repeat(64),engineVersion:backend==="lightpanda"?"1.0.2":"Chrome 151.0.7922.34",
  engineSHA256:backend==="lightpanda"?"ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e":"1".repeat(64),
  archiveSHA256:"2".repeat(64),sandboxEvidence:{ownedRenderer:true,chromiumFlagsSafe:true,rendererSeccomp:2,additionalSeccompFilter:true,rendererNamespaceSeparated:true},boundary:{memoryMax:"2147483648",cpuMax:"100000 100000",tasksMax:"256"},
  uid:1001,networkProbe:{local:"connected",nonlocal:"denied"},
  eligibleForComparison:true,forcedCleanup:false,engineExited:true,checks:[{name:"common",passed:true}],
  startupMs:1,coldCorpus:{toolCalls:3},warm:Array.from({length:5},()=>({toolCalls:3})),
  rss:{samples:5,readFailures:0}};
}
test("accepts matching correct receipts and emits no ratio",()=>{
 const result=compareWorkerReceipts(receipt("lightpanda"),receipt("playwright"));
 assert.equal(result.identityAndCorpusMatched,true);
 assert.equal(result.requiresIndependentNetworkBoundaryVerification,true);assert.equal("ratio" in result,false);
});
test("rejects mismatched host, fixture, boundaries, failures and corpus",()=>{
 for(const mutate of [
  x=>x.hostBinding="other",x=>x.fixtureSHA256="other",x=>x.boundary.tasksMax="64",
  x=>x.eligibleForComparison=false,x=>x.checks[0].passed=false,
  x=>x.uid=0,x=>x.networkProbe.nonlocal="connected",x=>x.sandboxEvidence=null,
  x=>x.checks[0].name="different",x=>x.warm[0].toolCalls=4,x=>x.rss.readFailures=1,
 ]){const b=receipt("playwright");mutate(b);assert.throws(()=>compareWorkerReceipts(receipt("lightpanda"),b));}
});
