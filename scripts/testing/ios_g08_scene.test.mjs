import test from "node:test";
import assert from "node:assert/strict";
import {iosG08Scene} from "./ios_g08_scene.mjs";
import {g08Workflow} from "../../tests/capture/g08-fixture.mjs";

test("retains the shared warmup and calibration facts and rejects invalid evidence", () => {
  const scene = {documentId: "fixture", viewport: {width: 800, height: 600},
    visualViewport: {x: 0, y: 0, width: 800, height: 600, scale: 1}, trusted: false};
  const event = (target, timeMs, center) => ({...scene, target, timeMs, center});
  const finish = {x: 50, y: 60};
  const events = [event("finish", 0, finish), event("finish", 3500, finish),
    event("start", 7000, {x: 200, y: 300}), event("finish", 10500, finish)];
  assert.deepEqual(iosG08Scene({events, dropped: 0}),
    {warmup: events[0], calibration: events[1], start: events[2], finish: events[3]});
  assert.throws(() => iosG08Scene({events: events.slice(1), dropped: 0}));
  assert.throws(() => iosG08Scene({events, dropped: 1}));
  assert.throws(() => iosG08Scene({events: [events[0], {...events[1], timeMs: 3499}, ...events.slice(2)], dropped: 0}));
  const workflow = g08Workflow("fixture-tab", "c");
  assert.equal(workflow.capture.maxDurationMs, 33000);
  assert.equal(workflow.capture.fps, 20);
  assert.equal(workflow.capture.maxBytes, 33554432);
});
