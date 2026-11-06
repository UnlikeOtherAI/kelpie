import {test} from "node:test";
import assert from "node:assert/strict";
import {runPngSpeedPair} from "./png-speed-serial.mjs";
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
