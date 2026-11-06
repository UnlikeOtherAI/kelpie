import assert from "node:assert/strict";

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

// This verifies accounting only. It never tolerates a missing, rounded or unmatched output frame.
export function validateCalibrationCase(item, decodedTicks, decodedHashes){
 assert.ok(item&&["stable","varying"].includes(item.name),"CALIBRATION_CASE");
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
 const sourceUnique=new Set(source).size,decodedUnique=new Set(decodedHashes).size;
 if(item.name==="stable")assert.equal(sourceUnique,1,"CALIBRATION_SOURCE_UNSTABLE");
 else {assert.ok(sourceUnique>=2,"CALIBRATION_NEGATIVE_SOURCE");assert.ok(decodedUnique>=2,"CALIBRATION_NEGATIVE_DECODED");}
 return {name:item.name,accepted:source.length,appendRejected:item.appendRejected,sourceUnique,decodedUnique,
  acceptedTicks:ticks,sourceROIHashes:source,decodedROIHashes:decodedHashes,
  observation:item.name==="stable"?(decodedUnique>1?"decoded-variation-after-input":"decoded-identical"):"varying-negative"};
}
