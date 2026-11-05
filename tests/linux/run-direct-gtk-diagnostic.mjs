#!/usr/bin/env node
// Direct owned GNOME diagnostic: never records readiness credentials or raw logs.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { control, rawRequest, bearerHeaders } from "../windows/lib/http.mjs";
import { startBrowser, stopBrowser, delay } from "../windows/lib/process.mjs";
import { readNativeIdentity, waitForNativeRetirement, verifyClosedSocket } from "./native-lifecycle.mjs";
import { runGtkStop } from "./gtk-stop.mjs";

const [binaryArg, expectedHash, outputArg] = process.argv.slice(2);
assert.ok(binaryArg && /^[a-f0-9]{64}$/.test(expectedHash ?? "") && outputArg);
assert.equal(process.env.GDK_BACKEND, "wayland");
const binary = await realpath(resolve(binaryArg)), output = resolve(outputArg);
await mkdir(output, { recursive: false, mode: 0o700 });
const runtime = await mkdtemp("/tmp/kelpie-direct-gtk-");
const profile = join(runtime, "profile");
await mkdir(profile, { mode: 0o700 });
const readinessPath = join(profile, "readiness.json");
const digest = createHash("sha256").update(await readFile(binary)).digest("hex");
assert.equal(digest, expectedHash);
const report = { source: process.env.KELPIE_CAPTURE_SOURCE, testSource: process.env.KELPIE_TEST_REVISION,
  binarySHA256: digest, stages: [], cleanup: "not-started" };
const stage = name => report.stages.push({ name, elapsedMs: Math.round(performance.now() - began) });
const began = performance.now();
let browser, identity, readiness, failed = false;
const cancel = new AbortController();
const deadline = setTimeout(() => cancel.abort(), 150000);
try {
  stage("spawn");
  browser = startBrowser(binary, ["--port", "0", "--profile-dir", profile,
    "--readiness-file", readinessPath, "--width", "1280", "--height", "900", "--url", "about:blank"]);
  if (!browser.child.pid) throw Error("spawn_error");
  identity = await readNativeIdentity(browser.child.pid);
  if (!identity || await realpath("/proc/" + identity.pid + "/exe") !== binary) throw Error("identity_mismatch");
  stage("spawned");
  const end = performance.now() + 30000;
  while (performance.now() < end && !cancel.signal.aborted) {
    if (browser.child.exitCode !== null || browser.child.signalCode !== null) throw Error("early_exit");
    try {
      const candidate = JSON.parse(await readFile(readinessPath, "utf8"));
      if (!Number.isInteger(candidate.port) || candidate.port < 1 || candidate.port > 65535 ||
          typeof candidate.token !== "string" || !candidate.token || typeof candidate.launchId !== "string")
        throw Error("readiness_invalid");
      readiness = candidate;
      break;
    } catch (error) {
      if (error.code !== "ENOENT") throw Error("readiness_invalid");
    }
    await delay(100);
  }
  if (!readiness) throw Error("readiness_timeout");
  const current = await readNativeIdentity(identity.pid);
  if (!current || current.startTicks !== identity.startTicks ||
      await realpath("/proc/" + identity.pid + "/exe") !== binary) throw Error("identity_mismatch");
  report.identity = { pid: identity.pid, startTicks: identity.startTicks, port: readiness.port };
  stage("ready");
  try { await control(readiness, "get-device-info"); } catch { throw Error("http_failure"); }
  stage("http");
  const mcp = await rawRequest({ port: readiness.port, path: "/mcp", headers: bearerHeaders(readiness.token),
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "direct-gtk-diagnostic", version: "1" } } }) });
  if (mcp.status !== 200 || !mcp.json?.result?.serverInfo) throw Error("mcp_failure");
  stage("mcp");
  try {
    const result = await runGtkStop({ readiness, identity, binary, hash: digest, output,
      env: process.env, signal: cancel.signal, sanitizeFailure: true });
    report.gtk = { invoked: result.action?.invoked === true, recovered: result.recovered === true,
      resultCode: result.result?.code, artifacts: result.artifacts.length };
  } catch { throw Error("atspi_or_gtk_failure"); }
  stage("complete");
} catch (error) {
  const allowed = new Set(["spawn_error", "identity_mismatch", "early_exit", "readiness_invalid",
    "readiness_timeout", "http_failure", "mcp_failure", "atspi_or_gtk_failure"]);
  stage(allowed.has(error.message) ? error.message : "diagnostic_failure");
  failed = true;
} finally {
  clearTimeout(deadline);
  if (browser) {
    const logs = browser.logs(), stderr = logs.stderrFirst + logs.stderr;
    report.stderr = { boundedBytes: Buffer.byteLength(stderr),
      display: /gtk|wayland|display/i.test(stderr), sandbox: /sandbox|zygote/i.test(stderr),
      bindOrPermission: /address already in use|permission denied|eacces|eaddrinuse/i.test(stderr),
      profileOrReadiness: /profile|readiness/i.test(stderr), library: /shared librar|cannot open shared/i.test(stderr),
      other: stderr.length > 0 };
    report.exit = { code: browser.child.exitCode, signal: browser.child.signalCode };
    try {
      await stopBrowser(browser, { gracefulClose: readiness ? () => control(readiness, "close-browser") : undefined,
        timeoutMs: 10000 });
      if (!readiness) { report.cleanup = "owned-process-only"; failed = true; }
      else {
        await waitForNativeRetirement(identity);
        await verifyClosedSocket(readiness.port);
        try { await readFile(readinessPath); throw Error("readiness retained"); }
        catch (error) { if (error.code !== "ENOENT") throw error; }
        report.cleanup = "public-close-and-retirement";
      }
    } catch { report.cleanup = "failed"; failed = true; }
  }
  const remaining = identity ? await readNativeIdentity(identity.pid) : undefined;
  if (!remaining || remaining.startTicks !== identity.startTicks) {
    await rm(runtime, { recursive: true, force: true });
    report.privateRuntimeRemoved = true;
  } else {
    report.privateRuntimeRemoved = false;
    failed = true;
  }
  await writeFile(join(output, "direct-gtk-diagnostic.json"), JSON.stringify(report, null, 2));
}
if (failed) process.exitCode = 1;
