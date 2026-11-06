import test from "node:test";
import assert from "node:assert/strict";
import {validateCalibrationCase,decodedTicksAt600,classifyMarkerRegime,redExcess} from "./script-video-calibration-check.mjs";
const a="a".repeat(64),b="b".repeat(64),c="c".repeat(64),hashes={clean:a,varying:b,"small-faint":b};
const make=name=>({name,accepted:Array.from({length:40},(_,i)=>{
 const alternate=name==="varying"?Math.floor(i/5)%2===1:name==="small-faint"&&i<20;
 return {tick:(i+1)*30,sourceROIHash:alternate?b:a,sourceKind:alternate?"alternate":"clean"};
}),appendRejected:0,encodedFrames:40});
const ticks=item=>item.accepted.map(record=>record.tick);
test("calibration retains exact matching PTS and observes rather than assumes codec stability",()=>{
 const stable=make("stable"),same=Array(40).fill(a),varied=same.map((x,i)=>i>=20?c:x);
 assert.equal(validateCalibrationCase(stable,ticks(stable),same,hashes).observation,"decoded-identical");
 assert.equal(validateCalibrationCase(stable,ticks(stable),varied,hashes).observation,"decoded-variation-after-input");
 const negative=make("varying");assert.equal(validateCalibrationCase(negative,ticks(negative),varied,hashes).observation,"varying");
 const marker=make("small-faint");assert.equal(validateCalibrationCase(marker,ticks(marker),varied,hashes).sourceUnique,2);
});
test("calibration fails closed on missing, reordered, ambiguous or mislabeled evidence",()=>{
 const stable=make("stable"),same=Array(40).fill(a),t=ticks(stable);
 assert.throws(()=>validateCalibrationCase(stable,t.slice(1),same,hashes),/CALIBRATION_OUTPUT_COUNT/);
 assert.throws(()=>validateCalibrationCase(stable,[...t.slice(0,1),...t.slice(2),t[1]],same,hashes),/CALIBRATION_PTS_MISMATCH/);
 assert.throws(()=>validateCalibrationCase({...stable,encodedFrames:39},t,same,hashes),/CALIBRATION_COMMITTED_COUNT/);
 assert.throws(()=>validateCalibrationCase({...stable,accepted:stable.accepted.map(x=>({...x,tick:30}))},t,same,hashes),/CALIBRATION_INPUT_TICKS/);
 assert.throws(()=>validateCalibrationCase(make("varying"),t,same,hashes),/CALIBRATION_NEGATIVE_DECODED/);
 const marker=make("small-faint");marker.accepted[0].sourceKind="clean";
 assert.throws(()=>validateCalibrationCase(marker,t,same,hashes),/CALIBRATION_SOURCE_KIND/);
});
test("track time base converts to writer ticks only when rationally exact",()=>{
 assert.deepEqual(decodedTicksAt600([60,120],"1/1200"),[30,60]);
 assert.deepEqual(decodedTicksAt600([50,100],"1/1000"),[30,60]);
 assert.throws(()=>decodedTicksAt600([51],"1/1000"),/CALIBRATION_PTS_ROUNDING/);
 assert.throws(()=>decodedTicksAt600([30],"0/600"),/CALIBRATION_TIME_BASE/);
 assert.throws(()=>decodedTicksAt600([1.5],"1/600"),/CALIBRATION_OUTPUT_PTS/);
});
test("fixed red excess and independent clean controls fail closed",()=>{
 const roi=Buffer.alloc(97*97*3,255);roi[0]=255;roi[1]=250;roi[2]=250;
 assert.equal(redExcess(roi),5); // red over white: red itself did not change
 assert.equal(classifyMarkerRegime([2,3,4,5],[2,3,4,5],[8,9,10,11],[1,2,3,4]).status,"encoded-visible");
 assert.equal(classifyMarkerRegime([2,3,4,5],[2,3,4,6],[8,9,10,11],[1,2,3,4]).reason,"clean-control");
 assert.equal(classifyMarkerRegime([2,3,4,5],[2,3,4,5],[4,9,10,11],[1,2,3,4]).reason,"marker-indistinguishable");
 assert.equal(classifyMarkerRegime([2,3,4,5],[2,3,4,5],[8,9,10,11],[1,2,3,6]).reason,"clean-control");
 assert.throws(()=>classifyMarkerRegime([0,0,0,NaN],[0,0,0,0],[1,1,1,1],[0,0,0,0]),/CALIBRATION_METRIC/);
 assert.equal(classifyMarkerRegime([2],[2,3,4,5],[8,9,10,11],[1,2,3,4]).reason,"sample-count");
});
