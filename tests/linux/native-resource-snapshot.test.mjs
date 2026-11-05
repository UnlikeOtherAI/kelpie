import { test } from "node:test";
import assert from "node:assert/strict";
import { nativeProcessStartTicks, parseProcStat, snapshotNativeResources } from "./native-resource-snapshot.mjs";

test("stat parser handles parentheses in process name", () => {
  const fields = ["S", "17", ...Array(15).fill("0"), "4", "0", "12345"];
  assert.deepEqual(parseProcStat(`42 (name ) with spaces) ${fields.join(" ")}`),
    { ppid: 17, threads: 4, startTicks: "12345" });
  assert.equal(parseProcStat("invalid"), null);
});
test("identity mismatch cannot expose resource counts", async () => {
  const snapshot = await snapshotNativeResources({ pid: process.pid, startTicks: "0", sequence: 4 });
  assert.equal(snapshot.identityValid, false);
  assert.equal(snapshot.complete, false);
  assert.equal(snapshot.processCount, undefined);
});
test("real Linux process yields only bounded fixed data", { skip: process.platform !== "linux" }, async () => {
  const startTicks = await nativeProcessStartTicks(process.pid);
  assert.match(startTicks, /^\d+$/);
  const snapshot = await snapshotNativeResources({ pid: process.pid, startTicks, sequence: 7 });
  assert.equal(snapshot.identityValid, true);
  assert.equal(snapshot.sequence, 7);
  assert.ok(snapshot.processCount >= 1);
  assert.ok(snapshot.threads >= 1);
  assert.match(snapshot.monotonicNs, /^\d+$/);
  assert.deepEqual(Object.keys(snapshot).sort(), [
    "complete", "fds", "identityValid", "maxFds", "maxThreads", "monotonicNs", "processCount",
    "pid", "rootNofileHard", "rootNofileSoft", "startTicks", "sequence", "shmAvailableBytes", "shmBytes", "sockets", "threads", "vanishedOrUnreadable",
  ].sort());
});
