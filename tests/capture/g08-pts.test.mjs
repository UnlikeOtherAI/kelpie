import test from "node:test";
import assert from "node:assert/strict";
import {validateG08PTS} from "./g08-pts.mjs";
const artifact={width:640,height:360,timestamps:[0,0.05,0.1]};
const metadata=()=>({streams:[{width:640,height:360}],frames:[0,0.05,0.1].map(t=>({best_effort_timestamp_time:String(t)}))});
test("actual media PTS and geometry agree with supplied evidence",()=>{
  assert.deepEqual(validateG08PTS(metadata(),artifact),artifact.timestamps);
});
test("missing, substituted, repeated PTS and wrong geometry fail closed",()=>{
  for(const mutate of [
    m=>{m.frames[1].best_effort_timestamp_time=null;},
    m=>{m.frames[1].best_effort_timestamp_time="0.06";},
    m=>{m.frames[1].best_effort_timestamp_time="0";},
    m=>{m.streams[0].width=320;},
    m=>{m.frames.pop();},
  ]){const m=metadata();mutate(m);assert.throws(()=>validateG08PTS(m,artifact));}
});
