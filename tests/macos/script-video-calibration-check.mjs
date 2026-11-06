import assert from "node:assert/strict";

export const markerControls=[
 {name:"small-faint",radiusPx:3,alpha:0.02,color:"#ff0000",anchor:"pointer-tip"},
 {name:"small-visible",radiusPx:3,alpha:0.10,color:"#ff0000",anchor:"pointer-tip"},
 {name:"medium-faint",radiusPx:8,alpha:0.02,color:"#ff0000",anchor:"pointer-tip"},
];
export const caseNames=["stable","varying","holdout",...markerControls.map(item=>item.name)];

// Convert the declared track time base exactly; never round a decoded timestamp.
export function decodedTicksAt600(values,timeBase){
 assert.ok(typeof timeBase==="string"&&/^[1-9]\d{0,8}\/[1-9]\d{0,8}$/.test(timeBase),"CALIBRATION_TIME_BASE");
 const [numerator,denominator]=timeBase.split("/").map(BigInt);
 return values.map(value=>{
  assert.ok(Number.isSafeInteger(value)&&value>=0,"CALIBRATION_OUTPUT_PTS");
  const scaled=BigInt(value)*numerator*600n;
  assert.equal(scaled%denominator,0n,"CALIBRATION_PTS_ROUNDING");
  const ticks=scaled/denominator;
  assert.ok(ticks<=BigInt(Number.MAX_SAFE_INTEGER),"CALIBRATION_OUTPUT_PTS");
  return Number(ticks);
 });
}

// This verifies accounting only. No missing, rounded or unmatched output frame is tolerated.
export function validateCalibrationCase(item,decodedTicks,decodedHashes,sourceHashes,imageHashes){
 assert.ok(item&&caseNames.includes(item.name),"CALIBRATION_CASE");
 assert.ok(Array.isArray(item.accepted)&&item.accepted.length>=16&&item.accepted.length<=40,"CALIBRATION_ACCEPTED");
 assert.ok(Number.isInteger(item.appendRejected)&&item.appendRejected>=0&&item.appendRejected<=24,"CALIBRATION_REJECTED");
 assert.equal(item.accepted.length+item.appendRejected,40,"CALIBRATION_ATTEMPTS");
 assert.equal(item.encodedFrames,item.accepted.length,"CALIBRATION_COMMITTED_COUNT");
 assert.ok(Array.isArray(decodedTicks)&&Array.isArray(decodedHashes)&&decodedTicks.length===item.accepted.length&&decodedHashes.length===decodedTicks.length,"CALIBRATION_OUTPUT_COUNT");
 const ticks=item.accepted.map(record=>record.tick);
 assert.ok(ticks.every((tick,index)=>Number.isInteger(tick)&&tick>=30&&tick<=1200&&tick%30===0&&(!index||tick>ticks[index-1])),"CALIBRATION_INPUT_TICKS");
 assert.deepEqual(decodedTicks,ticks,"CALIBRATION_PTS_MISMATCH");
 const source=item.accepted.map(record=>record.sourceROIHash);
 assert.ok(source.every(hash=>/^[a-f0-9]{64}$/.test(hash))&&decodedHashes.every(hash=>/^[a-f0-9]{64}$/.test(hash)),"CALIBRATION_HASH");
 const sourceImages=item.accepted.map(record=>record.sourceImageHash);
 assert.ok(sourceImages.every(hash=>/^[a-f0-9]{64}$/.test(hash)),"CALIBRATION_IMAGE_HASH");
 const kinds=item.accepted.map(record=>record.sourceKind);
 for(let i=0;i<ticks.length;i++){
  const index=ticks[i]/30-1;
  const alternate=item.name==="varying"?Math.floor(index/5)%2===1:markerControls.some(control=>control.name===item.name)&&index<20;
  assert.equal(kinds[i],alternate?"alternate":"clean","CALIBRATION_SOURCE_KIND");
  assert.equal(source[i],alternate?sourceHashes[item.name]:sourceHashes.clean,"CALIBRATION_SOURCE_IDENTITY");
  assert.equal(sourceImages[i],alternate?imageHashes[item.name]:imageHashes.clean,"CALIBRATION_IMAGE_IDENTITY");
 }
 const sourceUnique=new Set(source).size,decodedUnique=new Set(decodedHashes).size;
 if(item.name==="stable"||item.name==="holdout")assert.equal(sourceUnique,1,"CALIBRATION_SOURCE_UNSTABLE");
 if(item.name==="varying"){assert.ok(sourceUnique>=2,"CALIBRATION_NEGATIVE_SOURCE");assert.ok(decodedUnique>=2,"CALIBRATION_NEGATIVE_DECODED");}
 return {name:item.name,accepted:source.length,appendRejected:item.appendRejected,sourceUnique,decodedUnique,
  acceptedTicks:ticks,sourceROIHashes:source,sourceImageHashes:sourceImages,sourceKinds:kinds,decodedROIHashes:decodedHashes,
  observation:item.name==="stable"?(decodedUnique>1?"decoded-variation-after-input":"decoded-identical"):item.name};
}

// Fixed ROI metric: summed positive red excess over the larger green/blue channel.
export function redExcess(rgb){
 assert.ok(Buffer.isBuffer(rgb)&&rgb.length===97*97*3,"CALIBRATION_ROI");
 let sum=0;for(let i=0;i<rgb.length;i+=3)sum+=Math.max(0,rgb[i]-Math.max(rgb[i+1],rgb[i+2]));
 return sum;
}

// Training sets the sole boundary; independently encoded holdout and clean tail must both pass.
export function classifyMarkerRegime(training,holdout,marker,tail){
 const sets=[training,holdout,marker,tail];
 assert.ok(sets.every(values=>Array.isArray(values)&&values.every(value=>Number.isSafeInteger(value)&&value>=0&&value<=97*97*255)),"CALIBRATION_METRIC");
 if(sets.some(values=>values.length<4))return {status:"insufficient",reason:"sample-count"};
 const boundary=Math.max(...training),holdoutMax=Math.max(...holdout),tailMax=Math.max(...tail),markerMin=Math.min(...marker);
 const clean=holdoutMax<=boundary&&tailMax<=boundary,detected=markerMin>boundary;
 return {status:clean&&detected?"encoded-visible":"insufficient",reason:!clean?"clean-control":!detected?"marker-indistinguishable":"separated",
  boundary,holdoutMax,tailMax,markerMin,trainingCount:training.length,holdoutCount:holdout.length,markerCount:marker.length,tailCount:tail.length};
}
