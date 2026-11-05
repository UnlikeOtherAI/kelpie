import assert from "node:assert/strict";
import { readFile, stat, lstat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { REQUIREMENTS, validateEvidence } from "./evidence.mjs";

export const NATIVE_VARIANTS = [
  ["windows", "chromium", "desktop", "windowed"], ["linux", "chromium", "desktop", "windowed"],
  ["linux", "chromium", "desktop", "offscreen"],
  ["macos", "webkit", "desktop", "windowed"], ["macos", "chromium", "desktop", "windowed"],
  ["ios", "webkit", "phone", "windowed"], ["ios", "webkit", "tablet", "windowed"],
  ["android", "chromium", "phone", "windowed"], ["android", "chromium", "tablet", "windowed"],
];
const protocols = ["http", "mcp-direct", "mcp-generic", "cli"];
const variant = record => [record.platform, record.renderer, record.deviceClass, record.runtimeMode].join(":");
export function nativeCoverage(report) {
  validateEvidence(report);
  const known = new Set(NATIVE_VARIANTS.map(parts => parts.join(":")));
  const rows = NATIVE_VARIANTS.flatMap(([platform, renderer, deviceClass, runtimeMode]) => REQUIREMENTS.map(requirement => {
    const records = report.records.filter(record => record.requirement === requirement &&
      variant(record) === [platform, renderer, deviceClass, runtimeMode].join(":"));
    const builds = new Map();
    for (const record of records) {
      if (record.status !== "passed" || record.kind !== "real-interface" || !record.protocol) continue;
      const key = [record.revision, record.binarySha256, record.installedVersion].join(":");
      const build = builds.get(key) ?? { revision: record.revision, binarySha256: record.binarySha256,
        installedVersion: record.installedVersion, protocols: new Set(), artifacts: [] };
      build.protocols.add(record.protocol); build.artifacts.push(...record.artifacts); builds.set(key, build);
    }
    const machineEvidence = [...builds.values()].map(build => ({ ...build, protocols: [...build.protocols].sort(),
      completeProtocolSet: protocols.every(protocol => build.protocols.has(protocol)) }));
    return { requirement, platform, renderer, deviceClass, runtimeMode, machineEvidence,
      sourceOrUnitRecords: records.filter(record => ["source-review", "unit"].includes(record.kind)).length,
      uiRecords: records.filter(record => ["manual-ui", "native-ui"].includes(record.kind) && record.status === "passed").map(record => ({
        kind: record.kind, uiDriver: record.uiDriver, protocol: record.protocol,
        result: record.result, entryPoint: record.entryPoint,
        revision: record.revision, binarySha256: record.binarySha256, artifacts: record.artifacts,
      })),
      mediaRecords: records.filter(record => record.kind === "manual-media" && record.status === "passed").map(record => ({
        revision: record.revision, binarySha256: record.binarySha256, artifacts: record.artifacts,
        visualObservation: record.visualObservation,
      })),
      blockers: records.filter(record => record.status === "blocked").map(record => record.blocker),
      failures: records.filter(record => record.status === "failed").map(record => ({ revision: record.revision,
        binarySha256: record.binarySha256, kind: record.kind, protocol: record.protocol, result: record.result })),
      pendingRecords: records.filter(record => record.status === "pending").length,
      // No automatic acceptance: scope, semantic outcomes, decode and real UI need review.
      acceptance: "unreviewed" };
  }));
  return { version: 1, rows, unclassifiedRecords: report.records.filter(record => !known.has(variant(record))).length };
}
export async function verifyEvidenceArtifacts(report, artifactRoot) {
  validateEvidence(report);
  const root = path.resolve(artifactRoot), checked = new Map();
  for (const record of report.records.filter(record => record.status === "passed")) for (const artifact of record.artifacts) {
    const file = path.resolve(root, artifact.path);
    const relative = path.relative(root, file);
    assert.ok(relative && !relative.startsWith(".." + path.sep) && relative !== ".." && !path.isAbsolute(relative), "Artifact outside root");
    // Refuse symlink traversal through any component, not only the final file.
    let current = root;
    assert.ok(!(await lstat(root)).isSymbolicLink(), "Symlink artifact root");
    for (const part of relative.split(path.sep)) {
      current = path.join(current, part);
      assert.ok(!(await lstat(current)).isSymbolicLink(), "Symlink artifact path");
    }
    if (!checked.has(file)) {
      const info = await stat(file);
      assert.ok(info.isFile() && info.size <= 268_435_456, "Artifact file/size refused");
      const hash = createHash("sha256");
      for await (const chunk of createReadStream(file)) hash.update(chunk);
      checked.set(file, hash.digest("hex"));
    }
    assert.equal(checked.get(file), artifact.sha256.toLowerCase(), "Artifact digest mismatch");
  }
  return { verifiedFiles: checked.size };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  assert.ok(process.argv[2] && process.argv[3], "Usage: node tests/capture/native-coverage.mjs <report.json> <artifact-root>");
  assert.ok((await stat(process.argv[2])).size <= 16 * 1024 * 1024, "Report too large");
  const report = JSON.parse(await readFile(process.argv[2], "utf8"));
  const verified = await verifyEvidenceArtifacts(report, process.argv[3]);
  console.log(JSON.stringify({ ...nativeCoverage(report), ...verified }));
}
