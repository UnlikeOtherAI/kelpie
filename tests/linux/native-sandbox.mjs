#!/usr/bin/env node
// Bounded real native HTTP/MCP and renderer-sandbox smoke. No desktop input.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, readdir, readlink, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createRequire } from "node:module";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
import { control, waitFor } from "../windows/lib/http.mjs";
import { fileExists, startBrowser, stopBrowser, waitForReadiness } from "../windows/lib/process.mjs";

assert.equal(process.platform, "linux");
const executable = resolve(process.argv[2]);
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { Client } = require("@modelcontextprotocol/sdk/client/index.js");
const { StreamableHTTPClientTransport } = require("@modelcontextprotocol/sdk/client/streamableHttp.js");
// Chromium uses AF_UNIX singleton sockets below TMPDIR (108-byte path limit).
// Keep runtime scratch short and private even when build caches are deeply nested.
const runtime = await mkdtemp("/tmp/kelpie-native-");
process.env.TMPDIR = runtime;
const profile = process.env.KELPIE_TEST_PROFILE ?? await mkdtemp(join(tmpdir(), "kelpie-linux-sandbox-"));
const readinessPath = join(profile, "readiness.json");
const fixture = await startCaptureFixture();
const browser = startBrowser(executable, ["--headless", "--port", "0", "--profile-dir", profile,
  "--readiness-file", readinessPath, "--width", "640", "--height", "480", "--url", fixture.url]);
const report = {
  source: process.env.KELPIE_TEST_REVISION ?? "unrecorded",
  binarySHA256: createHash("sha256").update(await readFile(executable)).digest("hex"),
  host: process.env.HOSTNAME ?? "linux", headless: true, runtime, profile, checks: [],
};
const execute = promisify(execFile);
let readiness, client;
async function descendants(root) {
  const entries = (await readdir("/proc")).filter(name => /^\d+$/.test(name));
  const parents = (await Promise.all(entries.map(async name => {
    try {
      const line = await readFile("/proc/" + name + "/stat", "utf8");
      const tail = line.slice(line.lastIndexOf(")") + 2).split(" ");
      return [Number(name), Number(tail[1])];
    } catch { return undefined; }
  }))).filter(Boolean);
  const owned = new Set([root]);
  for (let changed = true; changed;) {
    changed = false;
    for (const [pid, parent] of parents) if (owned.has(parent) && !owned.has(pid)) { owned.add(pid); changed = true; }
  }
  return [...owned].filter(pid => pid !== root);
}
async function namespace(pid, name) {
  const path = "/proc/" + pid + "/ns/" + name;
  try { return await readlink(path); }
  catch {
    // Read-only attestation of an already identified owned child; never a helper
    // installation, process mutation or kernel/SELinux policy change.
    return (await execute("sudo", ["-n", "readlink", path], { timeout: 3000 })).stdout.trim();
  }
}
try {
  readiness = await Promise.race([
    waitForReadiness(readinessPath, 30000),
    browser.exited.then(({ code, signal, error }) => {
      throw new Error("Native app exited before readiness: " + (error?.message ?? signal ?? code));
    }),
  ]);
  await waitFor(async () => (await control(readiness, "get-current-url")).url?.startsWith(fixture.url), "fixture navigation", 15000);
  const tabs = (await control(readiness, "get-tabs")).tabs;
  assert.ok(tabs.length > 0);
  report.device = await control(readiness, "get-device-info");
  report.checks.push("Real headless CEF navigation and authenticated native HTTP");
  const renderers = await waitFor(async () => {
    const result = [];
    for (const pid of await descendants(browser.child.pid)) {
      try {
        const args = (await readFile("/proc/" + pid + "/cmdline", "utf8")).split("\0");
        if (!args.includes("--type=renderer")) continue;
        const forbidden = args.filter(value => /^--(?:no-sandbox|disable-(?:namespace|seccomp-filter|setuid)-sandbox)(?:=|$)/.test(value));
        assert.deepEqual(forbidden, []);
        const text = await readFile("/proc/" + pid + "/status", "utf8");
        const field = name => new RegExp("^" + name + ":\\s*(.*)$", "m").exec(text)?.[1].trim();
        assert.equal(field("NoNewPrivs"), "1");
        assert.equal(field("Seccomp"), "2");
        const pidIds = field("NSpid")?.split(/\s+/);
        assert.ok(pidIds && pidIds.length >= 2);
        const user = await namespace(pid, "user"), network = await namespace(pid, "net"), pidSpace = await namespace(pid, "pid");
        assert.notEqual(user, await namespace(browser.child.pid, "user"));
        assert.notEqual(network, await namespace(browser.child.pid, "net"));
        assert.notEqual(pidSpace, await namespace(browser.child.pid, "pid"));
        result.push({ pid, noNewPrivs: 1, seccomp: 2, namespacePIDCount: pidIds.length, user, network, pidSpace });
      } catch (error) {
        if (error?.code === "ENOENT" || error?.code === "ESRCH") continue;
        throw error;
      }
    }
    return result.length ? result : false;
  }, "actual renderer sandbox attestation", 10000);
  report.renderers = renderers;
  report.checks.push("Actual renderer namespaces differ from browser; NoNewPrivs1/Seccomp2; no disabling flags");

  client = new Client({ name: "kelpie-linux-native-smoke", version: "1.0.0" }, { capabilities: {} });
  await client.connect(new StreamableHTTPClientTransport(new URL("http://127.0.0.1:" + readiness.port + "/mcp"), {
    requestInit: { headers: { Authorization: "Bearer " + readiness.token } },
  }), { timeout: 10000 });
  const tools = await client.listTools({}, { timeout: 10000 });
  assert.ok(tools.tools.length > 0 && tools.tools.every(tool => tool.name.startsWith("kelpie_")));
  report.mcpServer = client.getServerVersion(); report.tools = tools.tools.map(tool => tool.name);
  report.checks.push("Real native MCP initialize and capability catalogue");
  await client.close(); client = undefined;
  await stopBrowser(browser, { gracefulClose: () => control(readiness, "close-browser"), timeoutMs: 15000 });
  assert.equal(browser.child.exitCode, 0);
  assert.equal(await fileExists(readinessPath), false);
  report.checks.push("Authenticated shutdown retires exact owned app and readiness");
} finally {
  if (client) await client.close().catch(() => {});
  if (browser.child.exitCode === null && browser.child.signalCode === null)
    await stopBrowser(browser, { gracefulClose: readiness ? () => control(readiness, "close-browser") : undefined }).catch(() => {});
  await fixture.close();
  if (process.env.KELPIE_TEST_ARTIFACT_DIR) {
    await mkdir(process.env.KELPIE_TEST_ARTIFACT_DIR, { recursive: true });
    await writeFile(join(process.env.KELPIE_TEST_ARTIFACT_DIR, "linux-native-sandbox.json"), JSON.stringify(report, null, 2));
    await writeFile(join(process.env.KELPIE_TEST_ARTIFACT_DIR, "linux-native-app-logs.json"), JSON.stringify(browser.logs(), null, 2));
  }
  // Preserve the owned synthetic profile for failure/recovery inspection.
  console.log(JSON.stringify(report, null, 2));
}
