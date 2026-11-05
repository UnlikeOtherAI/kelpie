import test from "node:test";
import assert from "node:assert/strict";
import {iosG08Scene} from "./ios_g08_scene.mjs";

test("retains ordered calibration and rejects incomplete or dropped fixture facts", () => {
  const events = [{target: "finish", id: 1}, {target: "start", id: 2}, {target: "finish", id: 3}];
  assert.deepEqual(iosG08Scene({events, dropped: 0}), {calibration: events[0], start: events[1], finish: events[2]});
  assert.throws(() => iosG08Scene({events: events.slice(1), dropped: 0}));
  assert.throws(() => iosG08Scene({events, dropped: 1}));
});
