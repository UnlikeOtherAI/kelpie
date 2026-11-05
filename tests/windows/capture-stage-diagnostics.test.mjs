import test from "node:test";
import assert from "node:assert/strict";
import {parseCaptureStage as parse} from "./capture-stage-diagnostics.mjs";
test("accepts only bounded numeric stage records",()=>{
 assert.deepEqual(parse("KELPIE_CAPTURE_STAGE 100.000 10.000 20.500 30.000 40.000"),
  {elapsedMs:100,preMs:10,screenshotMs:20.5,postMs:30,encoderMs:40});
 assert.deepEqual(parse("KELPIE_CAPTURE_STAGE_TRUNCATED"),{truncated:true});
 for(const line of ["KELPIE_CAPTURE_STAGE -1.000 1.000 2.000 3.000 4.000",
  "KELPIE_CAPTURE_STAGE 300001.000 1.000 2.000 3.000 4.000",
  "KELPIE_CAPTURE_STAGE 1.000 2.000 3.000 4.000 5.000 secret","other"])assert.equal(parse(line),null);
});
