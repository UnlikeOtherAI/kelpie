import assert from "node:assert/strict";
import {evaluateG08} from "../capture/g08-timeline.mjs";
const rms=values=>Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
function interpolate(samples,time,maxGap,read){
 let before,after;
 for(const sample of samples){
  const value=read(sample);if(!value)continue;
  if(sample.timeMs<=time)before={time:sample.timeMs,value};
  if(sample.timeMs>=time){after={time:sample.timeMs,value};break;}
 }
 if(!before||!after||after.time-before.time>maxGap)return null;
 const fraction=after.time===before.time?0:(time-before.time)/(after.time-before.time);
 return before.value.map((value,index)=>value+(after.value[index]-value)*fraction);
}
function ensure(result){
 assert.equal(result?.analysis?.passed,true,"G08_INDEPENDENT_PASS_REQUIRED");
 assert.ok(Array.isArray(result.samples)&&result.samples.length>0&&result.samples.length<=600);
 assert.ok(result.samples.every((s,i)=>Number.isFinite(s.timeMs)&&(i===0||s.timeMs>result.samples[i-1].timeMs)),"G08_CLOCK");
 for(const key of ["pointerStartMs","markerStartMs","radiusBiasPx"])assert.ok(Number.isFinite(result.analysis[key]));
 assert.ok(Number.isFinite(result.analysis.endpointOffset?.x)&&Number.isFinite(result.analysis.endpointOffset?.y));
}
// Low-level metric helper only; it is not an acceptance result.
export function compareMeasuredPhases(native,exported){
 ensure(native);ensure(exported);
 const a=native.provenance,b=exported.provenance;
 assert.ok(a&&b&&/^[a-f0-9]{40}$/.test(a.source)&&/^[a-f0-9]{48}$/.test(a.runId));
 assert.ok(typeof a.documentId==="string"&&a.documentId.length>0&&a.documentId.length<=256);
 assert.ok(["c","s"].includes(a.curve)&&Number.isInteger(a.width)&&a.width>0&&a.width<=640&&Number.isInteger(a.height)&&a.height>0&&a.height<=1600);
 for(const key of ["source","runId","documentId","curve","width","height"])assert.equal(a[key],b[key],"G08_PROVENANCE_MISMATCH");
 const pointerErrors=[],alphaErrors=[],radiusErrors=[];
 const pointer=(result,phase)=>{
  const a=result.analysis;
  return interpolate(result.samples,a.pointerStartMs+phase*2400,288,s=>s.pointer&&Number.isFinite(s.pointer.x)&&Number.isFinite(s.pointer.y)?[s.pointer.x+a.endpointOffset.x,s.pointer.y+a.endpointOffset.y]:null);
 };
 const marker=(result,phase)=>{
  const a=result.analysis;
  return interpolate(result.samples,a.markerStartMs+phase*3000,360,s=>s.marker?.count>=20&&Number.isFinite(s.marker.alpha)&&Number.isFinite(s.marker.radius)?[s.marker.alpha,s.marker.radius-a.radiusBiasPx]:null);
 };
 for(let i=0;i<20;i++){
  const phase=.05+i*.9/19,a=pointer(native,phase),b=pointer(exported,phase);if(a&&b)pointerErrors.push(Math.hypot(a[0]-b[0],a[1]-b[1]));
  const markerPhase=.1+i*.7/19,c=marker(native,markerPhase),d=marker(exported,markerPhase);if(c&&d){alphaErrors.push(c[0]-d[0]);radiusErrors.push(c[1]-d[1]);}
 }
 assert.ok(pointerErrors.length>=15&&alphaErrors.length>=15,"INSUFFICIENT_EVIDENCE cross-stream brackets");
 const result={pointerSamples:pointerErrors.length,markerSamples:alphaErrors.length,pointerRmsPx:rms(pointerErrors),pointerMaxPx:Math.max(...pointerErrors),alphaRms:rms(alphaErrors),radiusRmsPx:rms(radiusErrors)};
 assert.ok(result.pointerRmsPx<=6&&result.pointerMaxPx<=12,"G08_CROSS_STREAM_POINTER_MISMATCH");
 assert.ok(result.alphaRms<=.12&&result.radiusRmsPx<=2.5,"G08_CROSS_STREAM_MARKER_MISMATCH");
 return result;
}

// Always rerun the common oracle on the actual sample arrays before comparing.
export function compareWgcExport(native,exported,config){
 const nativeAnalysis=evaluateG08(native.samples,config);
 const exportedAnalysis=evaluateG08(exported.samples,config);
 const comparison=compareMeasuredPhases({...native,analysis:nativeAnalysis},{...exported,analysis:exportedAnalysis});
 return {nativeAnalysis,exportedAnalysis,comparison};
}
