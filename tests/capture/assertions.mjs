import assert from "node:assert/strict";
import { normalizeSnapshot, normalizeObservationBundle } from "./normalization.mjs";

export const SECRET_CANARIES = ["PASSWORD", "DRAFT", "EDITOR", "HIDDEN", "JSONLD"]
  .map(kind => `CAPTURE_SECRET_${kind}_8137`);
export function assertValueFree(value) {
  const serialized = JSON.stringify(value);
  for (const secret of SECRET_CANARIES) assert.ok(!serialized.includes(secret), "A private fixture value escaped");
}
export function assertVisibleCenter(event, { tolerance = 2, trusted } = {}) {
  assert.equal(event.type, "click");
  if (trusted !== undefined) assert.equal(event.trusted, trusted, "Input trust differs from advertised guarantee");
  assert.ok(event.target, "No action target");
  assert.equal(event.hit, event.target, "A different element received the pointer");
  const bounds = event.visible;
  assert.ok(bounds.right > bounds.left && bounds.bottom > bounds.top, "Target has no visible area");
  assert.ok(Math.abs(event.x - (bounds.left + bounds.right) / 2) <= tolerance, "Pointer X missed visible center");
  assert.ok(Math.abs(event.y - (bounds.top + bounds.bottom) / 2) <= tolerance, "Pointer Y missed visible center");
}
export function assertCurvedTrajectory(points, { start, end, minimumDeviation = 2 } = {}) {
  assert.ok(points.length >= 5, "Need enough sampled pointer events to assess trajectory");
  const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  assert.ok(distance(points[0], start) <= 2, "Wrong trajectory start");
  assert.ok(distance(points.at(-1), end) <= 2, "Wrong trajectory end");
  const length = distance(start, end);
  assert.ok(length > 20, "Fixture trajectory is too short");
  const deviation = p => ((end.x - start.x) * (p.y - start.y) - (end.y - start.y) * (p.x - start.x)) / length;
  assert.ok(points.some(p => Math.abs(deviation(p)) >= minimumDeviation), "Trajectory is linear");
  for (let i = 1; i < points.length; i++) assert.ok(points[i].time > points[i - 1].time, "Non-increasing timestamps");
  const speed = (a, b) => distance(a, b) / (b.time - a.time);
  const middle = Math.floor(points.length / 2);
  const middleSpeed = speed(points[middle - 1], points[middle + 1]);
  assert.ok(speed(points[0], points[1]) < middleSpeed, "No ease-in evidence");
  assert.ok(speed(points.at(-2), points.at(-1)) < middleSpeed, "No ease-out evidence");
}
export function assertDifferentialObservations(left, right, { leftFixture = {}, rightFixture = {} } = {}) {
  assertValueFree(left); assertValueFree(right);
  assert.deepEqual(normalizeSnapshot(left, leftFixture), normalizeSnapshot(right, rightFixture));
}
export function assertDifferentialBundles(left, right, {
  leftFixture = {}, rightFixture = {}, inputGuarantees,
} = {}) {
  assertValueFree(left); assertValueFree(right);
  const a = normalizeObservationBundle(left, leftFixture);
  const b = normalizeObservationBundle(right, rightFixture);
  const guarantees = [a.inputGuarantee, b.inputGuarantee];
  if (inputGuarantees) {
    assert.deepEqual(guarantees, inputGuarantees, "Unexpected input guarantee");
    for (const guarantee of guarantees)
      assert.ok(["synthetic-coordinate", "trusted-coordinate"].includes(guarantee), "Unknown input guarantee");
    delete a.inputGuarantee; delete b.inputGuarantee;
  }
  assert.deepEqual(a, b);
  return { equivalent: true, inputGuarantees: guarantees };
}
