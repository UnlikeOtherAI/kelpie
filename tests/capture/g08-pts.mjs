import assert from "node:assert/strict";
// Reject absent, substituted or nonmonotonic timestamps; never infer FPS.
export function validateG08PTS(metadata,artifact){
  assert.equal(metadata.streams?.length,1);
  assert.equal(metadata.streams[0].width,artifact.width);
  assert.equal(metadata.streams[0].height,artifact.height);
  assert.ok(Array.isArray(metadata.frames));
  const actual=metadata.frames.map(frame=>{
    const value=frame.best_effort_timestamp_time;
    assert.ok(typeof value==="string"&&value.trim().length>0,"Missing decoded PTS");
    return Number(value);
  });
  assert.equal(actual.length,artifact.timestamps.length);
  assert.ok(actual.every((time,i)=>Number.isFinite(time)&&Number.isFinite(artifact.timestamps[i])&&
    Math.abs(time-artifact.timestamps[i])<0.000001&&(i===0||time>actual[i-1])),
    "Recorded timestamps differ from decoded media PTS");
  return actual;
}
