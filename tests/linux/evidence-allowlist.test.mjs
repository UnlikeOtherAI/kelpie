import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { summarize } from "../../scripts/ci/sanitize-linux-evidence.mjs";

const prefix = "dist/release/${{ matrix.distro.name }}/";
function paths(text, name) {
  const section = text.split("      - name: " + name)[1]?.split("          if-no-files-found:")[0];
  assert.ok(section);
  return section.split("          path: |")[1].trim().split(/\r?\n/).map(line => line.trim());
}
test("diagnostic uploads reject unknown or private paths", async () => {
  const native = await readFile(".github/workflows/linux-native.yml", "utf8");
  const resource = await readFile(".github/workflows/linux-resource-diagnostic.yml", "utf8");
  const smoke = scope => ["outcome.json", "installed-sha256.txt", "client-package-sha256.txt",
    "cgroup-before.txt", "cgroup-after.txt"].map(name => scope + "/" + name);
  const media = scope => ["gif", "mp4"].map(ext => scope + "/capture/count-mismatch." + ext);
  const expectedNative = ["safe-diagnostics.json", "namespace-diagnostic/outcome.json",
    "namespace-diagnostic/scope.txt", "namespace-diagnostic/installed-sha256.txt",
    "namespace-diagnostic/traced-exit.txt", ...smoke("installed-smoke"), ...media("installed-smoke"),
    ...smoke("installed-smoke-replay"), ...media("installed-smoke-replay")];
  const expectedResource = ["safe-diagnostics.json", "resource-expected.txt", "resource-scope.txt",
    "resource-test-revision.txt", "resource-image.txt", "resource-hook-diff.patch",
    ...smoke("installed-smoke-cli-only"), ...smoke("installed-smoke-resource"),
    ...media("installed-smoke-resource"), "installed-smoke-resource/capture/capture/resource-diagnostics.json"];
  for (const [text, name, expected] of [
    [native, "Upload installed-candidate diagnostics", expectedNative],
    [resource, "Upload bounded resource evidence", expectedResource],
  ]) {
    const list = paths(text, name).map(path => {
      assert.ok(path.startsWith(prefix));
      return path.slice(prefix.length);
    });
    assert.deepEqual(list.sort(), expected.sort());
    assert.equal(list.includes("installed-smoke/capture/private-unknown.json"), false);
    assert.equal(list.includes("namespace-diagnostic/app.log"), false);
  }
});
test("summary never copies arbitrary output or errors", async () => {
  const dir = await mkdtemp(join(tmpdir(), "kelpie-evidence-"));
  try {
    const path = join(dir, "installed-smoke", "capture");
    await mkdir(path, { recursive: true });
    await writeFile(join(path, "launch-report.json"), JSON.stringify({
      checks: [{ passed: true, error: "private-canary" }, { passed: false, name: "private-canary" }],
      corpus: { stderr: "private-canary" },
    }));
    const result = await summarize(dir);
    assert.deepEqual(result.scopes["installed-smoke"].native, { total: 2, passed: 1, failed: 1 });
    assert.doesNotMatch(JSON.stringify(result), /private-canary/);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
