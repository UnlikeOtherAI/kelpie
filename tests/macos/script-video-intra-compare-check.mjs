import assert from "node:assert/strict";
import {caseNames,decodedTicksAt600} from "./script-video-calibration-check.mjs";

// Only independently verified results from the same serial host may be compared.
export function compareArms(baseline,intra){
 assert.equal(baseline?.profile,"default");assert.equal(intra?.profile,"all-intra");
 assert.equal(baseline.scope,"synthetic-encoded-visible-marker-calibration");assert.equal(intra.scope,baseline.scope);
 assert.deepEqual(baseline.roi,intra.roi);assert.equal(baseline.metric,intra.metric);
 assert.equal(baseline.identity?.source,intra.identity?.source);
 assert.equal(baseline.identity?.writerSourceSHA256,intra.identity?.writerSourceSHA256);
 for(const key of ["compiler","ffmpeg","ffprobe","sdk","node","architecture"])
  assert.deepEqual(baseline.identity[key],intra.identity[key],"INTRA_ENVIRONMENT_MISMATCH");
 assert.match(baseline.identity.calibrationBinarySHA256,/^[a-f0-9]{64}$/);
 assert.match(intra.identity.calibrationBinarySHA256,/^[a-f0-9]{64}$/);
 assert.notEqual(baseline.identity.calibrationBinarySHA256,intra.identity.calibrationBinarySHA256,"INTRA_BINARY_IDENTITY");
 assert.equal(intra.identity.intraTransform?.sourceSHA256,baseline.identity.writerSourceSHA256);
 assert.equal(intra.identity.intraTransform?.insertion,"AVVideoMaxKeyFrameIntervalKey: 1");
 assert.match(intra.identity.intraTransform?.transformedSHA256??"",/^[a-f0-9]{64}$/);
 for(const arm of [baseline,intra]){
  assert.ok(arm.identity.process&&["elapsedSeconds","userSeconds","systemSeconds","maxResidentBytes"].every(k=>Number.isFinite(arm.identity.process[k])&&arm.identity.process[k]>=0),"INTRA_RESOURCE");
  assert.deepEqual(arm.results.map(item=>item.name),caseNames);
 }
 let defaultHasInter=false,intraAllI=true,sameInputs=true;const cases=[];
 for(let i=0;i<caseNames.length;i++){
  const a=baseline.results[i],b=intra.results[i];
  for(const item of [a,b]){
   assert.ok(Array.isArray(item.acceptedTicks)&&item.acceptedTicks.length>=16&&item.acceptedTicks.length<=40);
   assert.deepEqual(decodedTicksAt600(item.trackPTS,item.trackTimeBase),item.acceptedTicks,"INTRA_PTS");
   assert.equal(item.frameTypes.length,item.acceptedTicks.length);
   assert.ok(item.frameTypes.every(frame=>[0,1].includes(frame.key)&&["I","P","B"].includes(frame.type)));
   assert.ok(Number.isInteger(item.bytes)&&item.bytes>0&&item.bytes<=8*1024*1024);
  }
  defaultHasInter ||= a.frameTypes.some(frame=>frame.key===0||frame.type!=="I");
  intraAllI &&= b.frameTypes.every(frame=>frame.key===1&&frame.type==="I");
  for(const key of ["acceptedTicks","sourceROIHashes","sourceImageHashes","sourceKinds"])
   if(JSON.stringify(a[key])!==JSON.stringify(b[key]))sameInputs=false;
  cases.push({name:a.name,defaultBytes:a.bytes,intraBytes:b.bytes,defaultDropped:a.appendRejected,intraDropped:b.appendRejected,
   defaultFrameTypes:a.frameTypes.reduce((out,frame)=>(out[frame.type]=(out[frame.type]??0)+1,out),{}),
   intraFrameTypes:b.frameTypes.reduce((out,frame)=>(out[frame.type]=(out[frame.type]??0)+1,out),{})});
 }
 for(const arm of [baseline,intra])assert.ok(arm.results.reduce((sum,item)=>sum+item.bytes,0)<=8*1024*1024,"INTRA_BYTE_LIMIT");
 const reasons=[];if(!sameInputs)reasons.push("source-or-tick-mismatch");if(!defaultHasInter)reasons.push("default-has-no-interframes");
 if(!intraAllI)reasons.push("candidate-not-all-key-intra");
 return {scope:"synthetic-all-intra-control",status:reasons.length?"insufficient":"comparable",reasons,
  defaultProcess:baseline.identity.process,intraProcess:intra.identity.process,cases,
  defaultRegimes:baseline.regimes,intraRegimes:intra.regimes};
}
