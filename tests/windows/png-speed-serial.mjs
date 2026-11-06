import assert from "node:assert/strict";

// A runner must return its independently measured identities and cleanup, not
// just an exit code. Oracle insufficiency is retained and is not a launch error.
export async function runPngSpeedPair({expectedBinary,runArm}){
 assert.match(expectedBinary,/^[a-f0-9]{64}$/);assert.equal(typeof runArm,"function");
 const arms=[];
 for(const name of ["control","candidate"]){
  const result=await runArm(name);
  assert.equal(result.arm,name);assert.equal(result.dllSha256,expectedBinary);
  assert.equal(result.exeVerified,true);assert.equal(result.processAbsent,true);
  assert.equal(result.listenerAbsent,true);assert.equal(result.readinessAbsent,true);
  assert.equal(result.closedPublicly,true);assert.equal(result.caseFinished,true);
  assert.ok(["pass","insufficient","fail"].includes(result.oracle));
  arms.push(result);
 }
 return {order:["control","candidate"],cacheCaveat:"serial-order-and-cache-not-controlled",arms};
}
