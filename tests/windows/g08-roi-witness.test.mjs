import {test} from "node:test";
import assert from "node:assert/strict";
import {compareG08RoiWitness,validateG08RoiWitness} from "./g08-roi-witness.mjs";

const hash="a".repeat(64);
function receipt(){return {version:1,scope:"owned-g08-mp4-roi",format:"video/mp4",partial:false,writerDroppedFrames:0,truncated:false,
 source:"b".repeat(40),artifactSha256:hash,binarySha256:hash,ffprobeSha256:hash,
 binding:{fixtureListenerOwned:true,exactFixture:true,ownerCurrent:true,sameLease:true,sameDocument:true,viewportStable:true,postCaptureGrantCurrent:true},
 geometry:{width:640,height:406,left:438,top:161,right:522,bottom:245},
 rows:[{frameIndex:0,pts100ns:0,roiSha256:hash},{frameIndex:1,pts100ns:500000,roiSha256:hash}]};}
test("matches only complete MP4 rows to unique decoded PTS",()=>{
 assert.equal(compareG08RoiWitness(receipt(),[0,.05],0,1).sameInput,true);
 assert.throws(()=>validateG08RoiWitness(receipt(),[0,.0501]),/PTS_MISMATCH/);
 assert.throws(()=>validateG08RoiWitness(receipt(),[0,0]));
 assert.throws(()=>validateG08RoiWitness(receipt(),[0]));
});
test("refuses incomplete ownership, changed geometry, drop and arbitrary data",()=>{
 for(const [key,value] of [["partial",true],["writerDroppedFrames",1],["truncated",true],["format","image/gif"]])
  assert.throws(()=>validateG08RoiWitness({...receipt(),[key]:value},[0,.05]));
 assert.throws(()=>validateG08RoiWitness({...receipt(),binding:{...receipt().binding,sameDocument:false}},[0,.05]));
 assert.throws(()=>validateG08RoiWitness({...receipt(),geometry:{...receipt().geometry,width:639}},[0,.05]));
 assert.throws(()=>validateG08RoiWitness({...receipt(),url:"https://example.invalid"},[0,.05]));
 const bad=receipt();bad.rows[0].url="https://example.invalid";assert.throws(()=>validateG08RoiWitness(bad,[0,.05]));
});
