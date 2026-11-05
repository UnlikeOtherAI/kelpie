#!/usr/bin/env node
// Real packaged CLI registration/launch/MCP/recipe/stop; never seed running state or copy grants.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, mkdir, readFile, writeFile, realpath, access } from "node:fs/promises";
import { createHash } from "node:crypto";
import { join, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { readNativeIdentity, waitForNativeRetirement, verifyClosedSocket } from "./native-lifecycle.mjs";
const execute = promisify(execFile);
const [binaryArg, cliArg, outputArg] = process.argv.slice(2);
assert.equal(process.platform, "linux");
assert.ok(binaryArg && cliArg && outputArg);
const binary = resolve(binaryArg), cli = resolve(cliArg), output = resolve(outputArg);
await mkdir(output, { recursive: false });
const home = await mkdtemp("/tmp/kelpie-alias-"), cliHome = join(home, "cli"), profile = join(home, "profile");
await mkdir(cliHome, { mode: 0o700 }); await mkdir(join(home, "runtime"), { mode: 0o700 });
const env = { ...process.env, KELPIE_HOME: cliHome, TMPDIR: join(home, "runtime") };
const alias = "linux-offscreen-acceptance";
const deadline = new AbortController(), timer = setTimeout(() => deadline.abort(), 120000);
const report = { source: process.env.KELPIE_CAPTURE_SOURCE, cliSource: process.env.KELPIE_CLI_BUILD_REVISION,
  testSource: process.env.KELPIE_TEST_REVISION, checks: [], home, headless: true };
let launched = false, readinessPath, identity, failure;
const command = async (args, cleanup = false) => {
  const value = await execute(process.execPath, [cli, ...args], {
    env, timeout: cleanup ? 15000 : 90000, maxBuffer: 2097152,
    signal: cleanup ? AbortSignal.timeout(15000) : deadline.signal,
  });
  return JSON.parse(value.stdout);
};
try {
  report.binarySHA256 = createHash("sha256").update(await readFile(binary)).digest("hex");
  report.cliEntrySHA256 = createHash("sha256").update(await readFile(cli)).digest("hex");
  report.cliBundleSHA256 = createHash("sha256").update(await readFile(new URL("../dist/index.js", pathToFileURL(cli)))).digest("hex");
  report.cliVersion = (await execute(process.execPath, [cli, "--version"], { env, timeout: 5000 })).stdout.trim();
  assert.equal(report.cliVersion, JSON.parse(await readFile(new URL("../package.json", pathToFileURL(cli)), "utf8")).version);
  assert.equal((await command(["browser", "register", alias, "--platform", "linux", "--app-path", binary,
    "--profile-dir", profile])).success, true);
  const launch = await command(["browser", "launch", alias, "--headless"]);
  assert.equal(launch.success, true); launched = true;
  const store = JSON.parse(await readFile(join(cliHome, "browsers.json"), "utf8")), running = store.running[alias];
  assert.ok(Number.isInteger(running.pid) && running.pid > 1);
  readinessPath = running.readinessFile;
  assert.equal(resolve(readinessPath), join(profile, "readiness.json"));
  const ready = JSON.parse(await readFile(readinessPath, "utf8"));
  assert.equal(ready.launchId, running.launchId); assert.equal(ready.port, running.port);
  assert.equal(ready.controlMode, "loopback");
  assert.equal(await realpath("/proc/" + running.pid + "/exe"), await realpath(binary));
  const argv = (await readFile("/proc/" + running.pid + "/cmdline", "utf8")).split("\0");
  assert.ok(argv.includes("--headless"));
  identity = await readNativeIdentity(running.pid); assert.ok(identity);
  report.identity = { ...identity, launchId: running.launchId, port: running.port,
    readinessSchemaVersion: ready.version, actualHeadlessArgument: true };
  const headers = { authorization: "Bearer " + ready.token, "content-type": "application/json",
    accept: "application/json, text/event-stream" };
  const request = async (path, body) => {
    const current = JSON.parse(await readFile(readinessPath, "utf8"));
    assert.equal(current.launchId, ready.launchId); assert.equal(current.port, ready.port);
    const response = await fetch("http://127.0.0.1:" + ready.port + path, {
      method: "POST", headers, body: JSON.stringify(body), signal: deadline.signal,
    });
    assert.equal(response.status, 200); return response.json();
  };
  const info = await request("/v1/get-device-info", {});
  assert.equal(info.success, true); report.nativeAppVersion = info.app.version;
  const catalog = await request("/mcp", { jsonrpc: "2.0", id: 1, method: "tools/call",
    params: { name: "kelpie_extension_tools", arguments: { names: ["kelpie_play_script"] } } });
  assert.equal(catalog.error, undefined);
  const schemas = JSON.parse(catalog.result.content[0].text);
  assert.equal(schemas.ok, true);
  assert.ok(schemas.value.some(tool => tool.name === "kelpie_play_script" && tool.inputSchema));
  report.profileCatalog = { mode: "offscreen", playScriptAdvertised: true };
  const initialized = await request("/mcp", { jsonrpc: "2.0", id: 2, method: "initialize",
    params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "linux-alias-profile", version: "1" } } });
  report.nativeMcpServerInfo = initialized.result.serverInfo;
  report.checks.push({ name: "public Linux --headless alias launch and exact native identity", passed: true });
  const root = fileURLToPath(new URL("../../", import.meta.url));
  const observed = join(output, "observations.json");
  await execute(process.execPath, [join(root, "tests/windows/run-observation-acceptance.mjs"), readinessPath, observed],
    { env, timeout: 45000, signal: deadline.signal, maxBuffer: 2097152 });
  report.observations = JSON.parse(await readFile(observed, "utf8"));
  assert.ok(report.observations.checks.length > 0 && report.observations.checks.every(item => item.passed));
  const aliasOutput = join(output, "alias");
  await execute(process.execPath, [join(root, "tests/windows/run-alias-cli-acceptance.mjs"), cli, alias, cliHome, readinessPath, aliasOutput],
    { env, timeout: 90000, signal: deadline.signal, maxBuffer: 2097152 });
  const accepted = JSON.parse(await readFile(join(aliasOutput, "report.json"), "utf8"));
  assert.ok(accepted.checks.length >= 4 && accepted.checks.every(item => item.passed));
  report.checks.push(...accepted.checks);
} catch (error) { failure = error; report.failure = error.message; }
finally {
  clearTimeout(timer);
  if (launched) {
    try {
      assert.equal((await command(["browser", "stop", alias], true)).success, true);
      assert.ok(identity, "The native process must be pinned before claiming retirement");
      report.naturalExit = await waitForNativeRetirement(identity);
      report.socket = await verifyClosedSocket(report.identity.port);
      await assert.rejects(access(readinessPath), { code: "ENOENT" });
      assert.equal(JSON.parse(await readFile(join(cliHome, "browsers.json"), "utf8")).running[alias], undefined);
      report.cleanup = "supported public alias stop; readiness removed";
    } catch (error) { failure ??= error; report.cleanup = "failed"; report.cleanupError = error.message; }
  }
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ checks: report.checks.length, observations: report.observations?.checks.length,
    cleanup: report.cleanup, failed: Boolean(failure) }));
}
if (failure) process.exitCode = 1;
