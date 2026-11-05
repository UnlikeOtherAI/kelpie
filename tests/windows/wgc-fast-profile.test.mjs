import test from "node:test";
import assert from "node:assert/strict";
import {scriptPointerPosition} from "../../packages/shared/dist/index.js";
import {evaluateFastWgc} from "./wgc-fast-profile.mjs";
const config={from:{x:100,y:200},to:{x:500,y:200},curve:"c",viewport:{width:800,height:400}};
const canvas={width:400,height:200};
function samples(duration){
 return Array.from({length:15},(_,i)=>{
  const timeMs=i*50,p=scriptPointerPosition(config,(timeMs-100)/duration);
  return {timeMs,pointer:{x:p.x/2,y:p.y/2}};
 });
}
test("WGC canvas positions and actual PTS fit the CSS 350 ms motion",()=>{
 const result=evaluateFastWgc(samples(350),config,canvas);
 assert.equal(result.passed,true);
 assert.equal(result.input.samples[0].timeMs,0);
 assert.equal(result.input.samples[0].x,100);
 assert.ok(result.fit.fit500Px>result.fit.fit350Px+6);
});
test("500 ms motion and inadequate samples do not pass",()=>{
 assert.equal(evaluateFastWgc(samples(500),config,canvas).code,"FAST_DURATION_MISMATCH");
 assert.equal(evaluateFastWgc(samples(350).slice(0,2),config,canvas).code,"FAST_INSUFFICIENT_SAMPLES");
 assert.throws(()=>evaluateFastWgc(samples(350),config,{width:1,height:200}),/FAST_INVALID_VIEWPORT/);
});
