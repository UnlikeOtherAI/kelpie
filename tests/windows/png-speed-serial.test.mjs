import {test} from "node:test";
import assert from "node:assert/strict";
import {runPngSpeedPair} from "./png-speed-serial.mjs";
import {classifyOracle,classifyWrapperError} from "./run-hosted-png-speed-pair.mjs";
const hash="a".repeat(64);
const receipt=arm=>({arm,dllSha256:hash,exeVerified:true,processAbsent:true,listenerAbsent:true,
 readinessAbsent:true,closedPublicly:true,caseFinished:true,oracle:"insufficient"});
test("runs exact two arms serially and preserves oracle insufficiency",async()=>{
 const seen=[];const result=await runPngSpeedPair({expectedBinary:hash,runArm:async arm=>{seen.push(arm);return receipt(arm);}});
 assert.deepEqual(seen,["control","candidate"]);assert.equal(result.arms[0].oracle,"insufficient");
});
test("never starts candidate after cleanup or identity failure",async()=>{
 for(const key of ["processAbsent","listenerAbsent","readinessAbsent","closedPublicly","caseFinished","exeVerified","dllSha256"]){
  const seen=[];await assert.rejects(runPngSpeedPair({expectedBinary:hash,runArm:async arm=>{seen.push(arm);return {...receipt(arm),[key]:false};}}));
  assert.deepEqual(seen,["control"]);
 }
});
test("never hides a failed export behind an insufficient one",()=>{
 assert.equal(classifyOracle({results:[{passed:false,confidence:"insufficient"},{passed:false,confidence:"failed"}]}),"fail");
 assert.equal(classifyOracle({results:[{passed:true},{passed:false,confidence:"insufficient"}]}),"insufficient");
 assert.throws(()=>classifyOracle({results:[]}));
});
test("rejects interrupted and nonstandard wrapper exits",()=>{
 assert.equal(classifyWrapperError({code:1}),1);
 assert.throws(()=>classifyWrapperError({code:1,killed:true}));
 assert.throws(()=>classifyWrapperError({code:1,signal:"SIGTERM"}));
 assert.throws(()=>classifyWrapperError({code:2}));
});
