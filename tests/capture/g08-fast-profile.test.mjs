import {test} from "node:test";
import assert from "node:assert/strict";
import {scriptPointerPosition} from "../../packages/shared/dist/index.js";
import {fitFastPointer} from "./g08-fast-profile.mjs";
const geometry={from:{x:100,y:200},to:{x:500,y:200},curve:"s"};
function samples(duration,step=50,curve="s"){
 const out=[];
 for(let timeMs=0;timeMs<=700;timeMs+=step){
  const p=scriptPointerPosition({...geometry,curve},(timeMs-100)/duration);
  out.push({timeMs,...p});
 }
 return out;
}
test("350 ms canonical C and S tracks fit with independently bounded onset",()=>{
 for(const curve of ["c","s"]){
  const result=fitFastPointer(samples(350,50,curve),{...geometry,curve});
  assert.ok(result.fit350Px<2);assert.ok(result.fit500Px>result.fit350Px+6);
  assert.ok(result.intermediateSamples>=4);assert.ok(result.maximumGapMs<=100);
 }
});
test("500 ms control is rejected instead of relabelled 350",()=>{
 assert.throws(()=>fitFastPointer(samples(500),geometry),/FAST_DURATION_MISMATCH/);
});
test("endpoint-only and sparse records cannot establish fast motion",()=>{
 const data=samples(350);
 assert.throws(()=>fitFastPointer([data[0],data.at(-1)],geometry),/FAST_INSUFFICIENT_SAMPLES/);
 assert.throws(()=>fitFastPointer(samples(350,150),geometry),/FAST_INSUFFICIENT/);
});
test("nonmonotonic timestamps and inconsistent coordinates are rejected",()=>{
 const data=samples(350);data[4].timeMs=data[3].timeMs;
 assert.throws(()=>fitFastPointer(data,geometry),/FAST_INVALID_PTS/);
 const distorted=samples(350).map(p=>({...p,y:p.y+25}));
 assert.throws(()=>fitFastPointer(distorted,geometry),/FAST_INSUFFICIENT_ENDPOINT/);
});

test("quantized positions with a small fixed offset remain distinguishable",()=>{
 const measured=samples(350).map(p=>({...p,x:Math.round(p.x+2),y:Math.round(p.y-2)}));
 const fit=fitFastPointer(measured,geometry);
 assert.ok(fit.fit500Px>fit.fit350Px+6);
});