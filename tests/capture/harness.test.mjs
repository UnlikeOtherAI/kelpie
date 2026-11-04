import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { startCaptureFixture } from "./fixture-server.mjs";
import { assertVisibleCenter, assertCurvedTrajectory, assertValueFree, SECRET_CANARIES } from "./assertions.mjs";
import { validateEvidence, REQUIREMENTS } from "./evidence.mjs";

test("fixture serves synthetic targets and bounded event evidence", async () => {
  const fixture = await startCaptureFixture();
  try {
    const response = await fetch(fixture.url);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.match(html, /Confirm order/);
    assert.match(html, /application\/ld\+json/);
    assert.match(html, /CAPTURE_SECRET_PASSWORD_8137/);
    assert.equal((await fetch(fixture.url + "/events", { method: "POST", body: JSON.stringify({
      documentId: "fixture-document", type: "click", x: 42, y: 80,
    }) })).status, 202);
    const events = await (await fetch(fixture.url + "/events")).json();
    assert.equal(events.events.length, 1);
    assert.equal(events.dropped, 0);
    assert.equal((await fetch(fixture.url + "/events", { method: "POST", body: "invalid" })).status, 400);
    assert.equal((await fetch(fixture.url + "/events", { method: "POST", body: "x".repeat(16385) })).status, 413);
    assert.equal((await fetch(fixture.url + "/missing")).status, 404);
  } finally { await fixture.close(); }
});

test("geometry oracle catches noncenter, wrong hit and wrong trust", () => {
  const event = { type: "click", target: "unique", hit: "unique", trusted: false,
    x: 50, y: 25, visible: { left: 0, top: 0, right: 100, bottom: 50 } };
  assertVisibleCenter(event, { trusted: false });
  assert.throws(() => assertVisibleCenter({ ...event, x: 10 }));
  assert.throws(() => assertVisibleCenter({ ...event, hit: "cover" }));
  assert.throws(() => assertVisibleCenter(event, { trusted: true }));
});

test("trajectory oracle rejects linear or constant-speed movement", () => {
  const options = { start: { x: 0, y: 0 }, end: { x: 100, y: 0 } };
  const points = [[0, 0], [5, 4], [25, 15], [50, 20], [75, 15], [95, 4], [100, 0]]
    .map(([x, y], index) => ({ x, y, time: index * 20 }));
  assertCurvedTrajectory(points, options);
  assert.throws(() => assertCurvedTrajectory(points.map(p => ({ ...p, y: 0 })), options));
  assert.throws(() => assertCurvedTrajectory(points.map(p => ({ ...p, time: 0 })), options));
});

test("private canaries are forbidden in structured observations", () => {
  assertValueFree({ text: "Green tea" });
  for (const secret of SECRET_CANARIES) assert.throws(() => assertValueFree({ nested: { text: secret } }));
});

test("evidence cannot pass without provenance or pretend media was inspected", () => {
  const record = { requirement: "CAP-01", host: "fixture", platform: "macos", renderer: "webkit",
    revision: "a".repeat(40), reviewer: "acceptance", observedAt: "2026-11-04T00:00:00Z",
    result: "pending", status: "pending", kind: "manual-media" };
  assert.equal(validateEvidence({ version: 1, records: [record] }).records, 1);
  assert.throws(() => validateEvidence({ version: 1, records: [{ ...record, status: "passed" }] }));
  assert.throws(() => validateEvidence({ version: 1, records: [{ ...record, status: "blocked" }] }));
  const passed = { ...record, status: "passed", code: ["actual/source.swift"], steps: ["public MCP call"],
    artifacts: [{ path: "recording.mp4", sha256: "b".repeat(64) }],
    installedVersion: "test", binarySha256: "c".repeat(64), entryPoint: "direct MCP" };
  assert.throws(() => validateEvidence({ version: 1, records: [passed] }));
  assert.equal(validateEvidence({ version: 1, records: [{ ...passed, visualObservation: "Observed pointer fade" }] }).records, 1);
});

test("acceptance ledger and machine-readable IDs remain aligned", async () => {
  const ledger = await readFile(new URL("../../docs/plans/browser-automation-capture/acceptance.md", import.meta.url), "utf8");
  const ids = [...ledger.matchAll(/^\| ([A-Z]+-\d+) \|/gm)].map(match => match[1]);
  assert.deepEqual(ids, REQUIREMENTS);
});
