import test from "node:test";
import assert from "node:assert/strict";
import {parsePresentationTiming as parse} from "./presentation-timing-sanitizer.mjs";
test("accepts bounded fixed-code numeric facts and truncation markers",()=>{
  assert.deepEqual(parse("KELPIE_PRESENTATION_LATCH 123.000 75.250"),{kind:"latch",elapsedMs:123,durationMs:75.25});
  assert.deepEqual(parse("KELPIE_PRESENTATION_QUEUE 12.500 30.000 1"),{kind:"queue",elapsedMs:12.5,durationMs:30,latched:true});
  assert.deepEqual(parse("KELPIE_PRESENTATION_QUEUE_TRUNCATED"),{kind:"queue",truncated:true});
});
test("rejects untrusted extra text, wrong fields and out-of-bounds values",()=>{
  for(const value of ["KELPIE_PRESENTATION_QUEUE 1.000 2.000","KELPIE_PRESENTATION_LATCH 1.000 2.000 1",
    "KELPIE_PRESENTATION_QUEUE 1.000 2.000 1 secret","KELPIE_PRESENTATION_LATCH 300001.000 1.000",
    "KELPIE_PRESENTATION_LATCH -1.000 1.000","unrelated"]) assert.equal(parse(value),null);
});