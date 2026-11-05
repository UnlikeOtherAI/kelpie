import assert from "node:assert/strict";
import {test} from "node:test";
import {createNavigationResourceDiagnostic} from "./navigation-resource-diagnostic.mjs";

test("only navigation samples before and after without recording response text",async()=>{
  const order=[]; let saved;
  const diagnostic=createNavigationResourceDiagnostic({pid:123,startTicks:"456",output:".",
    snapshot:async({sequence})=>{order.push("sample");return {sequence,identityValid:true,complete:true};},
    sink:async(_path,data,options)=>{saved=JSON.parse(data);assert.equal(options.flag,"wx");}});
  assert.equal(await diagnostic.invoke("get-tabs",async()=>7),7);
  const response={success:false,error:{code:"NAVIGATION_ERROR",message:"ERR_INSUFFICIENT_RESOURCES private-canary"}};
  assert.equal(await diagnostic.invoke("navigate",async()=>{order.push("request");return response;}),response);
  await diagnostic.write();
  assert.deepEqual(order,["sample","request","sample"]);
  assert.equal(saved.snapshots[0].navigationError,1);assert.equal(saved.snapshots[0].insufficientResources,1);
  assert.equal(saved.snapshots[0].responseSuccess,0);assert.ok(!JSON.stringify(saved).includes("private-canary"));
});

test("observer failures and thrown requests preserve request semantics",async()=>{
  let saved,calls=0;const expected=Error("expected");
  const diagnostic=createNavigationResourceDiagnostic({pid:123,startTicks:"456",output:".",
    snapshot:async()=>{throw Error("unavailable");},sink:async(_path,data)=>{saved=JSON.parse(data);}});
  await assert.rejects(diagnostic.invoke("navigate",async()=>{calls++;throw expected;}),error=>error===expected);
  await diagnostic.write();assert.equal(calls,1);
  assert.equal(saved.snapshots[0].before.complete,false);assert.equal(saved.snapshots[0].after.complete,false);
  assert.equal(saved.snapshots[0].responseSuccess,-1);
});
