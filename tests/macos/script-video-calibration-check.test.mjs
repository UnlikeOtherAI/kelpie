import test from "node:test";
import assert from "node:assert/strict";
import {validateCalibrationCase} from "./script-video-calibration-check.mjs";
const a="a".repeat(64),b="b".repeat(64),c="c".repeat(64);
const make=name=>({name,accepted:Array.from({length:40},(_,i)=>({tick:(i+1)*30,sourceROIHash:name==="varying"&&i>=20?b:a})),appendRejected:0,encodedFrames:40});
const ticks=item=>item.accepted.map(record=>record.tick);
test("calibration retains exact matching PTS and observes rather than assumes codec stability",()=>{
 const stable=make("stable"),same=Array(40).fill(a),varied=same.map((x,i)=>i>=20?c:x);
 assert.equal(validateCalibrationCase(stable,ticks(stable),same).observation,"decoded-identical");
 assert.equal(validateCalibrationCase(stable,ticks(stable),varied).observation,"decoded-variation-after-input");
 const negative=make("varying");assert.equal(validateCalibrationCase(negative,ticks(negative),varied).observation,"varying-negative");
});
test("calibration fails closed on missing, reordered or ambiguous evidence",()=>{
 const stable=make("stable"),same=Array(40).fill(a),t=ticks(stable);
 assert.throws(()=>validateCalibrationCase(stable,t.slice(1),same),/CALIBRATION_OUTPUT_COUNT/);
 assert.throws(()=>validateCalibrationCase(stable,[...t.slice(0,1),...t.slice(2),t[1]],same),/CALIBRATION_PTS_MISMATCH/);
 assert.throws(()=>validateCalibrationCase({...stable,encodedFrames:39},t,same),/CALIBRATION_COMMITTED_COUNT/);
 assert.throws(()=>validateCalibrationCase({...stable,accepted:stable.accepted.map(x=>({...x,tick:30}))},t,same),/CALIBRATION_INPUT_TICKS/);
 assert.throws(()=>validateCalibrationCase(make("varying"),t,same),/CALIBRATION_NEGATIVE_DECODED/);
});
