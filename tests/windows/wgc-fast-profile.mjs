import assert from "node:assert/strict";
import {fitFastPointer} from "../capture/g08-fast-profile.mjs";

// WGC measurements are in the recorded canvas, while the fixture uses CSS pixels.
export function evaluateFastWgc(samples,config,canvas){
 assert.ok([canvas?.width,canvas?.height,config.viewport?.width,config.viewport?.height]
  .every(value=>Number.isFinite(value)&&value>0),"FAST_INVALID_VIEWPORT");
 const sx=config.viewport.width/canvas.width,sy=config.viewport.height/canvas.height;
 assert.ok(Math.abs(sx-sy)<0.03,"FAST_INVALID_VIEWPORT");
 const points=samples.filter(sample=>sample.pointer).map(sample=>({
  timeMs:sample.timeMs,x:sample.pointer.x*sx,y:sample.pointer.y*sy,
 }));
 const input={config:{from:config.from,to:config.to,curve:config.curve},canvas,
  viewport:config.viewport,samples:points};
 try{return {input,passed:true,fit:fitFastPointer(points,input.config)};}
 catch(error){
  const code=String(error.message??"").match(/^FAST_[A-Z_]+$/)?.[0]??"FAST_UNCLASSIFIED";
  return {input,passed:false,code};
 }
}
