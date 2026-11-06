import {test} from "node:test";
import assert from "node:assert/strict";
import {createHistoryProbe} from "./worker-comparison-history-probe.mjs";
test("distinguishes restored, normal, and absent root pageshow after anchored back",()=>{
 for(const [event,status] of [["r1","restored-from-bfcache"],["r0","normal-pageshow"],[null,"not-observed"]]){
  const p=createHistoryProbe();p.record("r0");p.record("n0");const mark=p.mark();if(event)p.record(event);
  assert.equal(p.result(mark).status,status);
 }
});
test("missing anchors, malformed messages and multiple root events fail closed",()=>{
 let p=createHistoryProbe();p.record("n0");let mark=p.mark();p.record("r1");assert.equal(p.result(mark).status,"insufficient");
 p=createHistoryProbe();p.record("r0");p.record("n0");mark=p.mark();p.record("private");assert.equal(p.result(mark).status,"insufficient");
 p=createHistoryProbe();p.record("r0");p.record("n0");mark=p.mark();p.record("r0");p.record("r1");assert.equal(p.result(mark).status,"ambiguous");
});
