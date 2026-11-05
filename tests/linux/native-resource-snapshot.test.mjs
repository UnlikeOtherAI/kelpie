import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createSnapshotBudget, nativeProcessStartTicks, parseProcStat, snapshotNativeResources } from "./native-resource-snapshot.mjs";

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
    "budgetExhausted", "complete", "fds", "identityValid", "maxFds", "maxThreads", "monotonicNs", "processCount",
    "pid", "rootNofileHard", "rootNofileSoft", "startTicks", "sequence", "shmAvailableBytes", "shmBytes", "sockets", "threads", "vanishedOrUnreadable",
  ].sort());
});

test("snapshot includes a live owned descendant", { skip: process.platform !== "linux" }, async () => {
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
  try {
    await once(child, "spawn");
    const startTicks = await nativeProcessStartTicks(process.pid);
    const result = await snapshotNativeResources({ pid: process.pid, startTicks, sequence: 8 });
    assert.equal(result.identityValid, true);
    assert.ok(result.processCount >= 2);
    assert.ok(result.threads >= 2);
  } finally {
    child.kill();
    await once(child, "exit");
  }
});
test("aggregate budget stops on elapsed time, processes, or fds", () => {
  let now = 0n;
  const timed = createSnapshotBudget({ now: () => now, milliseconds: 2 });
  assert.equal(timed.take("fds"), true);
  now = 2000000n;
  assert.equal(timed.take(), false);
  assert.deepEqual(timed.exhausted, { time: true, processes: false, fds: false });
  const processes = createSnapshotBudget({ now: () => 0n, processes: 1 });
  assert.equal(processes.take("processes"), true);
  assert.equal(processes.take("processes"), false);
  assert.equal(processes.exhausted.processes, true);
  const fds = createSnapshotBudget({ now: () => 0n, fds: 1 });
  assert.equal(fds.take("fds"), true);
  assert.equal(fds.take("fds"), false);
  assert.equal(fds.exhausted.fds, true);
});
test("exhaustion remains incomplete and rechecks root identity", async () => {
  let calls = 0;
  const budget = createSnapshotBudget({ now: () => 0n, milliseconds: 0 });
  const result = await snapshotNativeResources({ pid: 42, startTicks: "123", sequence: 9 }, {
    budget, getRootStat: async () => ({ ppid: 1, threads: 1, startTicks: ++calls === 1 ? "123" : "124" }),
  });
  assert.equal(calls, 2);
  assert.equal(result.identityValid, false);
  assert.equal(result.complete, false);
  assert.equal(result.budgetExhausted.time, true);
});