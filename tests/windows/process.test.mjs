import assert from "node:assert/strict";
import test from "node:test";

import { startBrowser } from "./lib/process.mjs";
import { parseOptions, readinessPath } from "./run-release-acceptance.mjs";

test("startBrowser resolves a normal owned child exit", async () => {
  const browser = startBrowser(process.execPath, ["-e", "process.exit(0)"]);
  const outcome = await browser.exited;
  assert.equal(outcome.code, 0);
  assert.equal(outcome.error, undefined);
});

test("startBrowser observes an executable spawn failure", async () => {
  const browser = startBrowser("C:\\kelpie-missing-executable-for-test.exe", []);
  const outcome = await browser.exited;
  assert.equal(outcome.code, null);
  assert(outcome.error instanceof Error);
});

test("acceptance options reject relative or foreign readiness paths", () => {
  const base = [
    "--exe", "C:\\kelpie.exe", "--cli", "C:\\kelpie-cli.js", "--nessie-root", "C:\\nessie",
    "--profile-dir", "C:\\owned-profile",
  ];
  assert.throws(() => parseOptions([...base, "--readiness-file", "readiness.json"]), /absolute/);
  const accepted = parseOptions([...base, "--readiness-file", "C:\\different-profile\\readiness.json"]);
  assert.throws(() => readinessPath(accepted, "C:\\owned-profile"), /inside the owned/);
});
