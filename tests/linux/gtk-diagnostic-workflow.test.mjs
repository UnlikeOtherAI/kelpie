import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const lint = readFileSync(".github/workflows/lint.yml", "utf8").replace(/\r\n/g, "\n");
const workflow = readFileSync(".github/workflows/linux-native.yml", "utf8").replace(/\r\n/g, "\n");
const script = readFileSync("scripts/ci/linux-gtk-diagnostic-build.sh", "utf8").replace(/\r\n/g, "\n");
const section = (text, start, end) => text.slice(text.indexOf(start), text.indexOf(end, text.indexOf(start) + start.length));
const build = section(workflow, "      - name: Build Fedora GTK startup diagnostic", "      - name: Upload Fedora GTK diagnostic");
const upload = section(workflow, "      - name: Upload Fedora GTK diagnostic", "      - name: Build Linux packages");
test("opt-in Fedora diagnostic leaves package and smoke steps in normal mode", () => {
  assert.match(lint, /linux_gtk_startup_diagnostic:[\s\S]*?default: false/);
  assert.match(lint, /linux-gtk-startup-diagnostic:[\s\S]*?gtk_diagnostic: true/);
  assert.match(build, /inputs\.gtk_diagnostic && matrix\.distro\.name == 'fedora-44'/);
  assert.match(workflow, /name: Build Linux packages\n        if: \$\{\{ !inputs\.gtk_diagnostic \}\}/);
  assert.match(workflow, /name: Verify installed Linux candidate\n        if: \$\{\{ !inputs\.gtk_diagnostic \}\}/);
  assert.equal((workflow.match(/always\(\) && !inputs\.gtk_diagnostic/g) ?? []).length, 2);
  assert.match(workflow, /test -z "\$\{RELEASE_TAG\}"/);
  assert.match(workflow, /test "\$\{EVENT_NAME\}" = workflow_dispatch/);
  assert.match(script, /test "\$\{source_revision\}" = "\$\{DIAGNOSTIC_SOURCE\}"/);
});
test("diagnostic builds only the app target and uploads an explicit narrow allowlist", () => {
  assert.match(script, /cmake --build apps\/linux\/build-gtk-diagnostic --target kelpie-linux/);
  assert.match(script, /-DKELPIE_LINUX_STARTUP_TEST_TRACE=ON/);
  assert.match(script, /scripts\/download-cef\.sh linux/);
  assert.doesNotMatch(script, /npm pack|package-linux|build-linux-runtime-bundle/);
  const paths = [...upload.matchAll(/dist\/gtk-diagnostic\/([^\s]+)/g)].map(match => match[1]);
  assert.deepEqual(paths, ["kelpie-linux", "manifest.json", "build-options.txt", "runtime-sha256.txt",
    "elf-dependencies.txt", "lock-sha256.txt", "cef-identity.txt", "checksums.txt"]);
  assert.match(upload, /if-no-files-found: error/);
});
test("the actual diagnostic shell and workflow run block parse as bash", () => {
  const shell = process.platform === "win32" ? "C:/Program Files/Git/bin/bash.exe" : "bash";
  const runBlock = build.split("        run: |\n")[1].split("\n").filter(line => line.startsWith("          ")).map(line => line.slice(10)).join("\n");
  assert.ok(runBlock.includes("docker run"));
  for (const source of [script, runBlock]) {
    const result = spawnSync(shell, ["-n"], { input: source, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr || result.error?.message);
  }
});
