import test from "node:test";
import assert from "node:assert/strict";
import {createG08Retention} from "./g08-retention.mjs";
test("warmup calibration retains the cleared stationary interval before the second marker",()=>{
 const r=createG08Retention({warmupCalibration:true,pointerMs:2400,markerMs:3000});
 for(let i=0;i<400;i++){
  const t=i*50,alpha=t===2000||t===7000?.7:0;
  r.push({timeMs:t,pointer:{x:1,y:1},marker:{alpha,roi:Buffer.from([i%256])}});
 }
 assert.equal(r.samples[40].calibrationCandidate,false);
 assert.equal(r.samples[100].calibrationCandidate,false);
 assert.equal(r.samples[139].calibrationCandidate,true);
 assert.equal(r.samples[140].calibrationCandidate,true);
 assert.equal(r.samples[141].calibrationCandidate,false);
 assert.ok(Buffer.isBuffer(r.samples[139].marker.roi));
 assert.equal(r.samples[100].marker.roi,undefined);
});
