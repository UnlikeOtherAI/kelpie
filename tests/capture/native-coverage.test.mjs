import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, mkdir, symlink, unlink, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { nativeCoverage, verifyEvidenceArtifacts } from "./native-coverage.mjs";
import { validateEvidence, REQUIREMENTS } from "./evidence.mjs";
const base = { requirement: "DIF-01", platform: "ios", renderer: "webkit", deviceClass: "phone", runtimeMode: "windowed",
  revision: "a".repeat(40), reviewer: "fixture-reviewer", host: "fixture",
  observedAt: "2026-11-05T00:00:00Z", result: "Synthetic validator case", status: "passed",
  kind: "real-interface", protocol: "http", binarySha256: "b".repeat(64), installedVersion: "test",
  entryPoint: "synthetic transport fixture", code: ["permanent/source"], steps: ["fixture only"],
  artifacts: [{ path: "data.bin", sha256: createHash("sha256").update("abc").digest("hex") }] };
const row = report => nativeCoverage(report).rows.find(r => r.requirement === "DIF-01" && r.platform === "ios" && r.deviceClass === "phone");
test("all48 IDs across nine native runtimes stay explicit and never become accepted", () => {
  const summary = nativeCoverage({ version: 1, records: [] });
  assert.equal(summary.rows.length, REQUIREMENTS.length * 9);
  assert.ok(summary.rows.every(r => r.acceptance === "unreviewed" && r.machineEvidence.length === 0));
  assert.equal(summary.rows.filter(r => r.platform === "linux").length, 96);
});
test("protocols combine only for the same exact native source, binary and installed version", () => {
  const records = ["http", "mcp-direct", "mcp-generic", "cli"].map(protocol => ({ ...base, protocol }));
  assert.equal(row({ version: 1, records }).machineEvidence[0].completeProtocolSet, true);
  records[3] = { ...records[3], binarySha256: "c".repeat(64) };
  assert.ok(row({ version: 1, records }).machineEvidence.every(build => !build.completeProtocolSet));
  const failure = { ...base, status: "failed", protocol: "cli", result: "Observed regression" };
  const failedRow = row({ version: 1, records: [failure] });
  assert.equal(failedRow.failures[0].result, "Observed regression");
  assert.equal(failedRow.machineEvidence.length, 0);
  const unit = { ...base, kind: "unit", protocol: undefined };
  assert.equal(row({ version: 1, records: [unit] }).machineEvidence.length, 0);
});
test("phone/tablet and GTK/OSR evidence coexist; unmarked/stub/worker evidence cannot fill native cells", () => {
  const records = [base, { ...base, deviceClass: "tablet" },
    { ...base, platform: "linux", renderer: "chromium", deviceClass: "desktop" },
    { ...base, platform: "linux", renderer: "chromium", deviceClass: "desktop", runtimeMode: "offscreen" },
    { ...base, runtimeMode: "stub" }, { ...base, deviceClass: "worker", runtimeMode: "worker" },
    { ...base, deviceClass: undefined }];
  assert.equal(validateEvidence({ version: 1, records }).records, 7);
  assert.equal(nativeCoverage({ version: 1, records }).unclassifiedRecords, 3);
  assert.throws(() => validateEvidence({ version: 1, records: [base, base] }));
});
test("artifact ingestion verifies bytes independently and refuses changed/missing/outside files", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "capture-native-coverage-"));
  try {
    await writeFile(path.join(directory, "data.bin"), "abc");
    const report = { version: 1, records: [base] };
    assert.equal((await verifyEvidenceArtifacts(report, directory)).verifiedFiles, 1);
    await mkdir(path.join(directory, "real"));
    await writeFile(path.join(directory, "real", "data.bin"), "abc");
    const link = path.join(directory, "link");
    await symlink(path.join(directory, "real"), link, "junction");
    try {
      await assert.rejects(verifyEvidenceArtifacts({ version: 1, records: [{ ...base,
        artifacts: [{ ...base.artifacts[0], path: "link/data.bin" }] }] }, directory), /Symlink/);
    } finally { await unlink(link); }
    await writeFile(path.join(directory, "data.bin"), "changed");
    await assert.rejects(verifyEvidenceArtifacts(report, directory), /digest mismatch/);
    await assert.rejects(verifyEvidenceArtifacts({ version: 1, records: [{ ...base,
      artifacts: [{ ...base.artifacts[0], path: "../outside" }] }] }, directory), /outside root/);
    await assert.rejects(verifyEvidenceArtifacts({ version: 1, records: [{ ...base,
      artifacts: [{ ...base.artifacts[0], path: "missing" }] }] }, directory));
  } finally {
    assert.ok(path.resolve(directory).startsWith(path.resolve(os.tmpdir()) + path.sep));
    await rm(directory, { recursive: true });
  }
});
