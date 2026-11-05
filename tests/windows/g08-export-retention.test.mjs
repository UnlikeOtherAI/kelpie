import test from "node:test";
import assert from "node:assert/strict";
import {observeG08Native,retainG08Exports} from "./g08-export-retention.mjs";
import {safeWgcDiagnostic} from "./wgc-safe-diagnostic.mjs";

const items=[{mimeType:"image/gif",id:"g"},{mimeType:"video/mp4",id:"m"}];
test("completed owned exports remain available when WGC failed",async()=>{
 const budget={remaining:100},calls=[];
 const native=observeG08Native(Promise.reject(new Error("WGC_CLOCK_NONINCREASING")));
 await new Promise(resolve=>setImmediate(resolve)); // Native fails before terminal arrives.
 const artifacts=await retainG08Exports({terminal:{success:true,runId:"owned",artifacts:items},
  activeRunId:"owned",budget,parse:item=>item,download:async(item,b)=>{calls.push(item.id);b.remaining-=10;return item;}});
 assert.deepEqual(calls,["g","m"]);assert.deepEqual(artifacts,items);assert.equal(budget.remaining,80);
 const outcome=await native;assert.equal(outcome.ok,false);assert.equal(outcome.error.message,"WGC_CLOCK_NONINCREASING");
 assert.equal(safeWgcDiagnostic("WGC_CLOCK_NONINCREASING").error,"WGC_CLOCK_NONINCREASING");
 assert.equal(safeWgcDiagnostic("WGC_CLOCK_NONPOSITIVE").error,"WGC_CLOCK_NONPOSITIVE");
});
test("failed or foreign terminal results cannot download exports",async()=>{
 for(const terminal of [{success:false,runId:"owned",artifacts:items},{success:true,runId:"other",artifacts:items},
  {success:true,runId:"owned",artifacts:[items[0],items[0]]}]){
  let calls=0;
  await assert.rejects(retainG08Exports({terminal,activeRunId:"owned",budget:{remaining:100},
   parse:item=>item,download:async()=>{calls++;}}));
  assert.equal(calls,0);
 }
});
