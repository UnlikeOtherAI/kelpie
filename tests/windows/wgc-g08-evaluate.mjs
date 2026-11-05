import assert from "node:assert/strict";
import {consumeWgcFrames} from "./wgc-frame-stream.mjs";
import {whiteBackedRGB} from "./wgc-g08-rgb.mjs";
import {measureG08Frame} from "../capture/g08-pixels.mjs";
import {evaluateG08} from "../capture/g08-timeline.mjs";
// No caller-provided analysis is accepted. Provenance must be verified by the
// orchestration layer before any cross-stream comparison.
export async function evaluateWgcFrames(stream,config){
 assert.ok(config&&["c","s"].includes(config.curve));
 const samples=[];let origin,calibrationStart,calibrationMarkerSeen=false,shape;
 const count=await consumeWgcFrames(stream,(bgra,meta)=>{
  if(origin===undefined)origin=meta.tick100ns;
  const dimensions=meta.width+":"+meta.height;
  if(shape)assert.equal(dimensions,shape,"WGC_SIZE_CHANGED");else shape=dimensions;
  const scale={x:meta.width/config.viewport.width,y:meta.height/config.viewport.height};
  assert.ok(Math.abs(scale.x-scale.y)<.01,"WGC_GEOMETRY_MISMATCH");
  const marker={center:{x:config.to.x*scale.x,y:config.to.y*scale.y},radius:config.radius*scale.x,color:config.color};
  const rgb=whiteBackedRGB(bgra,meta.width,meta.height,meta.alphaMode);
  const sample={timeMs:(meta.tick100ns-origin)/10000,...measureG08Frame(rgb,meta.width,meta.height,marker)};
  if(calibrationStart===undefined&&sample.pointer)calibrationStart=sample.timeMs;
  sample.calibrationCandidate=calibrationStart!==undefined&&!calibrationMarkerSeen&&sample.timeMs<=calibrationStart+8000;
  if(sample.marker.alpha>.2)calibrationMarkerSeen=true;
  samples.push(sample);
  const old=samples[samples.length-101];if(old&&!old.calibrationCandidate)delete old.marker.roi;
 });
 assert.equal(count,samples.length);
 const result=evaluateG08(samples,{...config,scale:{x:Number(shape?.split(":")[0])/config.viewport.width,y:Number(shape?.split(":")[1])/config.viewport.height}});
 return {samples,analysis:result,frameCount:count};
}
