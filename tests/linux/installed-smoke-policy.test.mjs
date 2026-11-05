import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
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
