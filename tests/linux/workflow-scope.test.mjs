import assert from "node:assert/strict";
import { test } from "node:test";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
test("native CI builds real Linux graph changes and refuses failed diffs", () => {
  const directory = mkdtempSync(join(tmpdir(), "kelpie-native-scope-"));
  const script = fileURLToPath(new URL("../../scripts/ci/linux-native-scope.sh", import.meta.url));
  const bash = process.env.KELPIE_TEST_BASH ?? (process.platform === "win32" ? "C:/Program Files/Git/bin/bash.exe" : "bash");
  const git = (...args) => execFileSync("git", args, { cwd: directory, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  const commit = (path, text) => {
    mkdirSync(dirname(join(directory, path)), { recursive: true }); writeFileSync(join(directory, path), text);
    git("add", "."); git("commit", "-qm", "scope fixture"); return git("rev-parse", "HEAD");
  };
  const changed = (base, head) => execFileSync(bash, [script, base, head],
    { cwd: directory, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  try {
    git("init", "-q");
    git("config", "user.name", "Scope fixture"); git("config", "user.email", "scope@example.invalid");
    git("config", "commit.gpgsign", "false");
    mkdirSync(join(directory, "empty-hooks")); git("config", "core.hooksPath", join(directory, "empty-hooks"));
    let base = commit("README.md", "base");
    let head = commit("README.md", "unrelated prose");
    assert.equal(changed(base, head), "build=false"); base = head;
    head = commit("apps/windows/src/fixture.cpp", "Windows only");
    assert.equal(changed(base, head), "build=false"); base = head;
    for (const path of ["apps/linux/src/fixture.cpp", "native/core-mcp/src/fixture.cpp",
      "packages/shared/src/browser-control/fixture.ts", "scripts/check-linux-script-codecs.sh",
      ".github/workflows/linux-native.yml", "pnpm-lock.yaml"]) {
      head = commit(path, "Linux build input");
      assert.equal(changed(base, head), "build=true", path); base = head;
    }
    const failed = spawnSync(bash, [script, "0".repeat(40), head], { cwd: directory, encoding: "utf8" });
    assert.notEqual(failed.status, 0); assert.ok(!failed.stdout.includes("build=false"));
  } finally {
    assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + sep));
    rmSync(directory, { recursive: true, force: true });
  }
});
