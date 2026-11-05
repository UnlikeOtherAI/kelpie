import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const REQUIREMENTS = [
  "OBS-01", "OBS-02", "OBS-03", "EXT-01", "EXT-02", "EXT-03", "EXT-04", "RDY-01", "RDY-02",
  "OWN-01", "OWN-02", "WFL-01", "WFL-02", "WFL-03", "WFL-04", "WFL-05",
  "TGT-01", "TGT-02", "TGT-03", "TGT-04", "TGT-05", "PTR-01", "PTR-02",
  "VIS-01", "VIS-02", "CAP-01", "CAP-02", "CAP-03", "CAP-04", "CAP-05", "CAP-06", "CAP-07", "CAP-08",
  "ART-01", "ART-02", "ART-03", "ART-04", "SEC-01", "SEC-02", "DIF-01", "LP-01", "LP-02",
  "WEB-01", "WEB-02", "DOC-01", "UI-01", "REL-01", "REL-02",
];
const nonempty = (value, name) => assert.ok(typeof value === "string" && value.trim().length, `Missing ${name}`);
export function validateEvidence(report) {
  assert.equal(report.version, 1);
  assert.ok(Array.isArray(report.records));
  const identities = new Set();
  for (const record of report.records) {
    assert.ok(REQUIREMENTS.includes(record.requirement), "Unknown requirement");
    for (const field of ["host", "platform", "renderer", "revision", "reviewer", "observedAt", "result"])
      nonempty(record[field], field);
    assert.match(record.revision, /^[0-9a-f]{40}$/i, "Use full exercised source SHA");
    assert.ok(Number.isFinite(Date.parse(record.observedAt)), "Invalid evidence date");
    assert.ok(["passed", "failed", "blocked", "pending"].includes(record.status));
    assert.ok(["source-review", "unit", "real-interface", "manual-ui", "manual-media"].includes(record.kind));
    if (record.deviceClass !== undefined) assert.ok(["desktop", "phone", "tablet", "worker"].includes(record.deviceClass), "Invalid device class");
    if (record.runtimeMode !== undefined) assert.ok(["windowed", "offscreen", "stub", "worker"].includes(record.runtimeMode), "Invalid runtime mode");
    if (record.protocol !== undefined) assert.ok(["http", "mcp-direct", "mcp-generic", "cli"].includes(record.protocol), "Invalid protocol");
    const identity = [record.requirement, record.platform, record.renderer, record.deviceClass ?? "unspecified",
      record.runtimeMode ?? "unspecified", record.kind, record.protocol ?? "unspecified", record.revision,
      record.binarySha256 ?? "unspecified", record.installedVersion ?? "unspecified"].join(":");
    assert.ok(!identities.has(identity), "Duplicate evidence identity");
    identities.add(identity);
    if (record.status === "blocked") nonempty(record.blocker, "blocker");
    if (record.status !== "passed") continue;
    assert.ok(Array.isArray(record.code) && record.code.length, "Pass needs implementation paths");
    assert.ok(Array.isArray(record.steps) && record.steps.length, "Pass needs reproducible steps");
    assert.ok(Array.isArray(record.artifacts) && record.artifacts.length, "Pass needs durable evidence");
    for (const artifact of record.artifacts) {
      nonempty(artifact.path, "artifact path");
      assert.match(artifact.sha256, /^[0-9a-f]{64}$/i, "Artifact needs independent SHA-256");
    }
    if (["real-interface", "manual-ui", "manual-media"].includes(record.kind)) {
      nonempty(record.installedVersion, "installed version");
      assert.match(record.binarySha256, /^[0-9a-f]{64}$/i, "Real flow needs exact binary SHA-256");
      nonempty(record.entryPoint, "public entry point");
    }
    if (record.kind === "manual-media") nonempty(record.visualObservation, "actual visual observation");
  }
  // This validates evidence shape, never promotes unit/source evidence to native acceptance.
  return { records: report.records.length, requirements: new Set(report.records.map(r => r.requirement)).size };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.ok(process.argv[2], "Usage: node tests/capture/evidence.mjs <report.json>");
  console.log(JSON.stringify(validateEvidence(JSON.parse(await readFile(process.argv[2], "utf8")))));
}
