import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { MOBY_COMMIT, MOBY_SHA256, makeProfile, namespaceRules } from "../../scripts/ci/linux-test-seccomp.mjs";

const allows = (rule, flags) => rule.args.every(arg =>
  ((flags >>> 0) & (arg.value >>> 0)) === (arg.valueTwo >>> 0));
test("pinned default rejects an unexpected source", () => {
  assert.match(MOBY_COMMIT, /^[a-f0-9]{40}$/);
  assert.match(MOBY_SHA256, /^[a-f0-9]{64}$/);
  assert.throws(() => makeProfile(Buffer.from("{}")), /baseline hash mismatch/);
});
test("test rules admit only scoped namespace calls on amd64", () => {
  const [clone, unshare] = namespaceRules;
  assert.deepEqual(clone.names, ["clone"]);
  assert.deepEqual(unshare.names, ["unshare"]);
  assert.deepEqual(clone.includes, { arches: ["amd64"] });
  assert.deepEqual(unshare.includes, { arches: ["amd64"] });
  for (const [flags, expected] of [[0x70000011, true], [0x10020011, false],
    [0x12000011, false], [0x14000011, false], [0x18000011, false], [0x20000011, false]])
    assert.equal(allows(clone, flags), expected, `clone 0x${flags.toString(16)}`);
  for (const [flags, expected] of [[0x10000000, true], [0x60000000, true],
    [0x00000600, true], [0x00020000, false], [0x02000000, false],
    [0x04000000, false], [0x08000000, false], [0x00000080, false]])
    assert.equal(allows(unshare, flags), expected, `unshare 0x${flags.toString(16)}`);
});

test("pinned upstream rules remain byte-for-byte equivalent after parsing",
  { skip: !process.env.KELPIE_SECCOMP_BASELINE }, () => {
    const bytes = readFileSync(process.env.KELPIE_SECCOMP_BASELINE);
    const baseline = JSON.parse(bytes.toString("utf8"));
    const profile = makeProfile(bytes);
    assert.deepEqual(profile.syscalls.slice(0, -2), baseline.syscalls);
    assert.deepEqual(profile.syscalls.slice(-2), namespaceRules);
    for (const key of Object.keys(baseline).filter(key => key !== "syscalls"))
      assert.deepEqual(profile[key], baseline[key]);
  });
