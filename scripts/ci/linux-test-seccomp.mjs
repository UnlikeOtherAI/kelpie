// Test-container seccomp profile: a pinned Moby default with narrowly scoped namespace additions.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export const MOBY_COMMIT = "4b8214fc4971e06172938a1f1554ccff6647ee80";
export const MOBY_SHA256 = "6416b47770785a41ac59073cdc77d9fe98517df2799dc83ef207e622de3053f6";
export const namespaceRules = [
  { names: ["clone"], action: "SCMP_ACT_ALLOW", args: [
    { index: 0, value: 503447552, valueTwo: 268435456, op: "SCMP_CMP_MASKED_EQ" },
  ], includes: { arches: ["amd64"] },
  comment: "Test only: clone requires NEWUSER and excludes NEWNS, NEWCGROUP, NEWUTS and NEWIPC" },
  { names: ["clone"], action: "SCMP_ACT_ALLOW", args: [
    { index: 0, value: 536870929, op: "SCMP_CMP_EQ" },
  ], includes: { arches: ["amd64"] },
  comment: "Test only: exact CLONE_NEWPID | SIGCHLD after Chromium enters its user namespace" },
  { names: ["unshare"], action: "SCMP_ACT_ALLOW", args: [
    { index: 0, value: 2415917567, valueTwo: 0, op: "SCMP_CMP_MASKED_EQ" },
  ], includes: { arches: ["amd64"] },
  comment: "Test only: unshare permits USER, PID, NET, FS and FILES flags only" },
];
export function makeProfile(bytes) {
  const hash = createHash("sha256").update(bytes).digest("hex");
  assert.equal(hash, MOBY_SHA256, "Pinned Moby seccomp baseline hash mismatch");
  const profile = JSON.parse(bytes.toString("utf8"));
  assert.equal(profile.defaultAction, "SCMP_ACT_ERRNO");
  assert.ok(Array.isArray(profile.syscalls));
  profile.syscalls.push(...structuredClone(namespaceRules));
  return profile;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , baseline, output] = process.argv;
  assert.ok(baseline && output, "Provide pinned baseline and fresh output paths");
  await writeFile(output, JSON.stringify(makeProfile(await readFile(baseline)), null, 2) + "\n", { flag: "wx" });
}
