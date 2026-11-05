import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import { spawnSync } from "node:child_process";
const workflow = await readFile(new URL("../../.github/workflows/linux-native.yml", import.meta.url), "utf8");
const script = await readFile(new URL("../../scripts/ci/linux-installed-smoke.sh", import.meta.url), "utf8");
test("installed smoke uses a separate bounded distro container and read-only source", () => {
  const smoke = workflow.slice(workflow.indexOf("      - name: Verify installed Linux candidate"));
  assert.equal((smoke.match(/docker run --rm --cpus=2 --memory=6g --pids-limit=512 --shm-size=256m/g) ?? []).length, 3);
  assert.doesNotMatch(workflow.slice(0, workflow.indexOf("      - name: Verify installed Linux candidate")), /--shm-size/);
  assert.match(smoke, /no-new-privileges=true/);
  assert.match(smoke, /linux-test-seccomp\.mjs/);
  assert.match(smoke, /seccomp=\$\{RUNNER_TEMP\}\/kelpie-test-seccomp\.json/);
  assert.match(smoke, /test-seccomp-sha256\.txt/);
  assert.match(smoke, /\$\{PWD\}:\/workspace:ro/);
  assert.match(smoke, /bash scripts\/ci\/linux-installed-smoke\.sh/);
  assert.doesNotMatch(smoke, /privileged|cap-add|seccomp=unconfined|apparmor=unconfined/);
});
test("exact distro package and installed binary are required before app admission", () => {
  assert.match(script, /apt-get install -y --no-install-recommends "\$candidate"/);
  assert.match(script, /dnf install -y "\$candidate"/);
  assert.match(script, /\$\{#candidates\[@\]\} == 1/);
  assert.match(script, /sha256sum \/usr\/bin\/kelpie-linux/);
  assert.ok(script.includes('$(cat /opt/kelpie/source-revision.txt)" == "$source_revision"'));
  assert.match(script, /unshare --user --map-root-user --net --pid --fork true/);
  assert.ok(script.indexOf("stage=sandbox-preflight") < script.indexOf("stage=native-http-mcp"));
  assert.doesNotMatch(script, /--no-sandbox|chmod 4755|sysctl|setenforce/);
});
test("supported native and packaged CLI interfaces plus independent media are exercised", () => {
  for (const name of ["run-native-capture-acceptance.mjs", "verify-native-replay.mjs", "run-native-alias-acceptance.mjs"])
    assert.ok(script.includes(name));
  assert.match(script, /runuser -u kelpie-smoke/);
  assert.match(script, /KELPIE_LINUX_FINALIZE_FAULT=1 KELPIE_LINUX_PREINPUT_REPLACEMENT=1/);
  assert.match(script, /timeout --signal=TERM --kill-after=10 300/);
  assert.match(workflow, /pnpm --filter @unlikeotherai\/kelpie build/);
  assert.match(workflow, /npm pack --ignore-scripts/);
});

test("package workflow shell parses before starting its build container", { skip: process.platform === "win32" }, () => {
  const block=workflow.split("      - name: Build Linux packages")[1]?.split("      - name: Verify installed Linux candidate")[0];
  assert.ok(block);
  const script=block.split("        run: |\n")[1];
  assert.ok(script);
  const result=spawnSync("bash",["-n"],{input:script.split("\n").map(line=>line.startsWith("          ")?line.slice(10):line).join("\n")});
  assert.equal(result.status,0,result.stderr.toString());
  const inner=script.split("bash -lc ")[1]?.split("' 2>&1")[0]?.slice(1);
  assert.ok(inner);
  const innerResult=spawnSync("bash",["-n"],{input:inner});
  assert.equal(innerResult.status,0,innerResult.stderr.toString());
  const broken=script.replace('awk "/^(CEF_ROOT', "awk '/^(CEF_ROOT").replace('):/ { print }" \"$cache\"', "):/ { print }' \"$cache\"");
  assert.notEqual(spawnSync("bash",["-n"],{input:broken}).status,0);
});
