import test from "node:test";
import assert from "node:assert/strict";
import {caseNames} from "./script-video-calibration-check.mjs";
import {compareArms} from "./script-video-intra-compare-check.mjs";
const hash="a".repeat(64),other="b".repeat(64),ticks=Array.from({length:16},(_,i)=>(i+1)*30);
function arm(profile){return {profile,scope:"synthetic-encoded-visible-marker-calibration",roi:[432,200,97,97],metric:"red",
 identity:{source:"1".repeat(40),writerSourceSHA256:hash,compiler:{sha256:hash},ffmpeg:{sha256:hash},ffprobe:{sha256:hash},
  sdk:"26",node:"20",architecture:"arm64",calibrationBinarySHA256:profile==="default"?hash:other,
  process:{elapsedSeconds:3,userSeconds:1,systemSeconds:.5,maxResidentBytes:1024},
  ...(profile==="all-intra"?{intraTransform:{sourceSHA256:hash,transformedSHA256:other,insertion:"AVVideoMaxKeyFrameIntervalKey: 1"}}:{})},
 regimes:[],results:caseNames.map(name=>({name,acceptedTicks:ticks,trackPTS:ticks,trackTimeBase:"1/600",
  sourceROIHashes:Array(16).fill(hash),sourceImageHashes:Array(16).fill(hash),sourceKinds:Array(16).fill("clean"),
  frameTypes:ticks.map((_,i)=>({key:profile==="default"&&i?0:1,type:profile==="default"&&i?"P":"I"})),bytes:100,appendRejected:24}))};}
test("serial arms require matched source and true key intra output",()=>{
 const base=arm("default"),intra=arm("all-intra");assert.equal(compareArms(base,intra).status,"comparable");
 intra.results[0].frameTypes[4]={key:0,type:"P"};assert.deepEqual(compareArms(base,intra).reasons,["candidate-not-all-key-intra"]);
});
test("mismatched source and time cannot be promoted",()=>{
 const base=arm("default"),intra=arm("all-intra");intra.results[0].sourceImageHashes=[...intra.results[0].sourceImageHashes];intra.results[0].sourceImageHashes[0]=other;
 assert.deepEqual(compareArms(base,intra).reasons,["source-or-tick-mismatch"]);
 intra.results[0].trackPTS=[...ticks];intra.results[0].trackPTS[0]++;
 assert.throws(()=>compareArms(base,intra),/INTRA_PTS/);
});

test("no inter-frame baseline and mismatched toolchain remain noncomparable",()=>{
 const base=arm("default"),intra=arm("all-intra");
 for(const item of base.results)item.frameTypes=ticks.map(()=>({key:1,type:"I"}));
 assert.deepEqual(compareArms(base,intra).reasons,["default-has-no-interframes"]);
 intra.identity.ffmpeg={sha256:other};
 assert.throws(()=>compareArms(base,intra),/INTRA_ENVIRONMENT_MISMATCH/);
});
