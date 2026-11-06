import assert from "node:assert/strict";

// The producer owns fixture/lease/grant validation. This verifier refuses
// any missing attestation rather than treating a page-provided nonce as proof.
export function validateG08RoiWitness(receipt,decodedPts){
 assert.equal(receipt?.version,1);assert.equal(receipt?.scope,"owned-g08-mp4-roi");
 assert.deepEqual(Object.keys(receipt).sort(),["binding","format","geometry","partial","rows","scope","truncated","version","writerDroppedFrames"]);
 assert.deepEqual(receipt?.binding,{fixtureListenerOwned:true,exactFixture:true,ownerCurrent:true,
  sameLease:true,sameDocument:true,viewportStable:true,postCaptureGrantCurrent:true});
 assert.deepEqual(receipt?.geometry,{width:640,height:406,left:438,top:161,right:522,bottom:245});
 assert.equal(receipt?.format,"video/mp4");assert.equal(receipt?.partial,false);
 assert.equal(receipt?.writerDroppedFrames,0);assert.equal(receipt?.truncated,false);
 assert.ok(Array.isArray(receipt?.rows)&&receipt.rows.length>=1&&receipt.rows.length<=800);
 assert.ok(Array.isArray(decodedPts)&&decodedPts.length===receipt.rows.length);
 let previous=-1;
 for(let index=0;index<receipt.rows.length;index++){
  const row=receipt.rows[index];
  assert.deepEqual(Object.keys(row).sort(),["frameIndex","pts100ns","roiSha256"]);
  assert.equal(row.frameIndex,index);assert.ok(Number.isSafeInteger(row.pts100ns)&&row.pts100ns>=0&&row.pts100ns>previous);
  assert.match(row.roiSha256,/^[a-f0-9]{64}$/);
  assert.ok(Number.isFinite(decodedPts[index])&&decodedPts[index]>=0);
  // Media Foundation timestamps are in 100 ns; decoded MP4 PTS may round to
  // a 50 microsecond track tick. Ambiguous/duplicate matches are refused.
  assert.ok(Math.abs(decodedPts[index]*1000-row.pts100ns/10000)<=0.051,"PTS_MISMATCH");
  if(index)assert.ok(decodedPts[index]>decodedPts[index-1]&&
   (decodedPts[index]-decodedPts[index-1])*1000>0.102,"PTS_AMBIGUOUS");
  previous=row.pts100ns;
 }
 return receipt.rows.map(({frameIndex,pts100ns,roiSha256})=>({frameIndex,pts100ns,roiSha256}));
}

export function compareG08RoiWitness(receipt,decodedPts,baselineIndex,tailIndex){
 const rows=validateG08RoiWitness(receipt,decodedPts);
 assert.ok(Number.isInteger(baselineIndex)&&Number.isInteger(tailIndex)&&baselineIndex>=0&&tailIndex>baselineIndex&&tailIndex<rows.length);
 return {baseline:rows[baselineIndex],tail:rows[tailIndex],sameInput:rows[baselineIndex].roiSha256===rows[tailIndex].roiSha256};
}
