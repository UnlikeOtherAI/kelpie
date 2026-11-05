import test from "node:test";
import assert from "node:assert/strict";
import {parseCaptureStage as parse} from "./capture-stage-diagnostics.mjs";
test("accepts only bounded numeric substage records",()=>{
 assert.deepEqual(parse("KELPIE_CAPTURE_STAGE 100.000 10.000 20.500 30.000 40.000 5.000 6.000"),
  {elapsedMs:100,preNavMs:10,preRemainingMs:20.5,screenshotMs:30,postNavMs:40,postViewportMs:5,encoderMs:6,preMs:30.5,postMs:45});
 assert.deepEqual(parse("KELPIE_CAPTURE_STAGE_TRUNCATED"),{truncated:true});
 for(const line of ["KELPIE_CAPTURE_STAGE -1.000 1.000 2.000 3.000 4.000 5.000 6.000",
  "KELPIE_CAPTURE_STAGE 300001.000 1.000 2.000 3.000 4.000 5.000 6.000",
  "KELPIE_CAPTURE_STAGE 1.000 2.000 3.000 4.000 5.000 6.000 7.000 secret","other"])assert.equal(parse(line),null);
});
