import assert from "node:assert/strict";

export function iosG08Scene(facts) {
  assert.equal(facts.dropped, 0);
  assert.deepEqual(facts.events.map(event => event.target), ["finish", "start", "finish"]);
  return {calibration: facts.events[0], start: facts.events[1], finish: facts.events[2]};
}
