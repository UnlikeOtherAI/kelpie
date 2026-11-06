#!/usr/bin/env node
// Direct owned GNOME diagnostic: never records readiness credentials or raw logs.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { control, rawRequest, bearerHeaders } from "../windows/lib/http.mjs";
import { startBrowser, stopBrowser, delay } from "../windows/lib/process.mjs";
import { readNativeIdentity, waitForNativeRetirement, verifyClosedSocket } from "./native-lifecycle.mjs";
import { runGtkStop } from "./gtk-stop.mjs";
import { verifyOwnedListener } from "./worker-comparison-listener.mjs";
import { parseGtkStartupTrace } from "./gtk-startup-trace.mjs";
import { parseGtkStartupAux } from "./gtk-startup-aux.mjs";
import { verifyGtkDiagnosticManifest } from "./gtk-diagnostic-manifest.mjs";
import { installHeadlessEnvironment } from "./headless-control-environment.mjs";

const [binaryArg, expectedHash, outputArg] = process.argv.slice(2);
assert.ok(binaryArg && /^[a-f0-9]{64}$/.test(expectedHash ?? "") && outputArg);
const mode = process.env.KELPIE_STARTUP_CONTROL_MODE ?? "windowed";
assert.ok(mode === "windowed" || mode === "headless");
const traceRequested = process.env.KELPIE_GTK_STARTUP_TRACE === "1";
const auxRequested = process.env.KELPIE_GTK_AUX_TRACE === "1";
if (auxRequested) assert.ok(traceRequested);
if (mode === "windowed") assert.equal(process.env.GDK_BACKEND, "wayland");
else {
  assert.ok(traceRequested);
  assert.equal(expectedHash, "cf23a2f1da2e335f03c001e17fa58d3d736e982d80851695f6f97e0de718df0c");
  assert.equal(process.env.KELPIE_GTK_BUILD_SOURCE, "0732d2ca8baf43130ea1c838afe7b38347f28179");
  assert.equal(process.env.KELPIE_GTK_BUILD_MANIFEST_SHA256, "4d692268ef3ab5673aad76d3177e3a100a5959e86b29ec36709d5cecd32ff9eb");
}
if (!traceRequested) assert.equal(expectedHash, "6439d5decf10b5a405f123612fa03ea55cb76a5ff3e5825d5f78d54711c2116c");
assert.equal(process.env.KELPIE_CAPTURE_SOURCE, "c42fc68d7fdfa01fae0cbe9cda82dc39bd8c4dc2");
assert.match(process.env.KELPIE_TEST_REVISION ?? "", /^[a-f0-9]{40}$/);
assert.equal(execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8", timeout: 5000 }).trim(),
  process.env.KELPIE_TEST_REVISION);
execFileSync("git", ["diff", "--quiet"], { timeout: 5000 });
execFileSync("git", ["diff", "--cached", "--quiet"], { timeout: 5000 });
const binary = await realpath(resolve(binaryArg)), output = resolve(outputArg);
const worktree = await realpath(process.cwd()), parent = await realpath(resolve(output, ".."));
const parentRelative = relative(worktree, parent);
assert.ok(parentRelative !== ".." && !parentRelative.startsWith(".." + sep) && !isAbsolute(parentRelative));
const digest = createHash("sha256").update(await readFile(binary)).digest("hex");
assert.equal(digest, expectedHash);
let buildIdentity;
if (traceRequested) {
  const manifestPath = await realpath(resolve(process.env.KELPIE_GTK_BUILD_MANIFEST ?? ""));
  const manifestRelative = relative(worktree, manifestPath);
  assert.ok(manifestRelative !== ".." && !manifestRelative.startsWith(".." + sep) && !isAbsolute(manifestRelative));
  assert.ok((await stat(manifestPath)).size <= 16384);
  buildIdentity = verifyGtkDiagnosticManifest(await readFile(manifestPath),
    process.env.KELPIE_GTK_BUILD_MANIFEST_SHA256, process.env.KELPIE_GTK_BUILD_SOURCE, digest);
  execFileSync("git", ["merge-base", "--is-ancestor", buildIdentity.diagnosticBuildSource, "HEAD"], { timeout: 5000 });
}
await mkdir(output, { recursive: false, mode: 0o700 });
const runtime = await mkdtemp(join(parent, ".private-runtime-"));
const profile = join(runtime, "profile");
await mkdir(profile, { mode: 0o700 });
const readinessPath = join(profile, "readiness.json");
const report = { ...(buildIdentity ?? { source: process.env.KELPIE_CAPTURE_SOURCE }),
  testSource: process.env.KELPIE_TEST_REVISION, binarySHA256: digest, mode,
  ...(mode === "headless" ? { nativeHeadlessSwitch: true, displayAndBusVariablesRemoved: true } : {}),
  stages: [], cleanup: "not-started" };
const stage = name => report.stages.push({ name, elapsedMs: Math.round(performance.now() - began) });
const began = performance.now();
let browser, identity, readiness, verified = false, acknowledged = false, failed = false;
const verify = () => verifyOwnedListener(identity.pid, readiness.port, identity.startTicks);
const cancel = new AbortController();
const deadline = setTimeout(() => cancel.abort(), 150000);
try {
  if (mode === "headless") installHeadlessEnvironment(process.env, runtime);
  stage("spawn");
  browser = startBrowser(binary, [...(mode === "headless" ? ["--headless"] : []), "--port", "0", "--profile-dir", profile,
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
  await verify();
  verified = true;
  report.identity = { pid: identity.pid, startTicks: identity.startTicks, port: readiness.port };
  stage("ready");
  try { await control(readiness, "get-device-info"); } catch { throw Error("http_failure"); }
  stage("http");
  await verify();
  const mcp = await rawRequest({ port: readiness.port, path: "/mcp", headers: bearerHeaders(readiness.token),
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "direct-gtk-diagnostic", version: "1" } } }) });
  if (mcp.status !== 200 || !mcp.json?.result?.serverInfo) throw Error("mcp_failure");
  stage("mcp");
  if (mode === "windowed") {
    await verify();
    try {
      const result = await runGtkStop({ readiness, identity, binary, hash: digest, output,
        env: process.env, signal: cancel.signal, sanitizeFailure: true });
      report.gtk = { invoked: result.action?.invoked === true, recovered: result.recovered === true,
        resultCode: result.result?.code, artifacts: result.artifacts.length };
    } catch { throw Error("atspi_or_gtk_failure"); }
  }
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
    if (traceRequested) {
      report.startupTrace = parseGtkStartupTrace(logs.stderrFirst, mode);
      report.startupTrace.stderrMayBeTruncated = logs.stderrFirst.length >= 32768;
      if (auxRequested) {
        report.auxiliaryTrace = parseGtkStartupAux(logs.stderrFirst, report.startupTrace, report.startupTrace.stderrMayBeTruncated, identity?.pid);
        if (report.auxiliaryTrace.state !== "observed") failed = true;
      }
      if (report.startupTrace.state !== "valid-prefix" || (mode === "headless" && report.startupTrace.stderrMayBeTruncated)) failed = true;
      if (mode === "headless" && readiness && !report.startupTrace.events.some(event => event.name === "PUBLISH_RETURNED")) failed = true;
    }
    report.stderr = { boundedBytes: Buffer.byteLength(stderr),
      display: /gtk|wayland|display/i.test(stderr), sandbox: /sandbox|zygote/i.test(stderr),
      bindOrPermission: /address already in use|permission denied|eacces|eaddrinuse/i.test(stderr),
      profileOrReadiness: /profile|readiness/i.test(stderr), library: /shared librar|cannot open shared/i.test(stderr),
      other: stderr.length > 0 };

    try {
      await stopBrowser(browser, { gracefulClose: verified ? async () => {
        await verify();
        const result = await control(readiness, "close-browser");
        assert.equal(result.accepted, true); acknowledged = true;
      } : undefined,
        timeoutMs: 10000 });
      if (!acknowledged) { report.cleanup = "owned-process-only"; failed = true; }
      else {
        await waitForNativeRetirement(identity);
        await verifyClosedSocket(readiness.port);
        try { await readFile(readinessPath); throw Error("readiness retained"); }
        catch (error) { if (error.code !== "ENOENT") throw error; }
        report.cleanup = "public-close-and-retirement";
      }
    } catch { report.cleanup = "failed"; failed = true; }
    report.exit = { code: browser.child.exitCode, signal: browser.child.signalCode };
  }
  const remaining = identity ? await readNativeIdentity(identity.pid) : undefined;
  const retired = identity ? (!remaining || remaining.startTicks !== identity.startTicks)
    : !browser?.child.pid || browser.child.exitCode !== null || browser.child.signalCode !== null;
  if (retired) {
    await rm(runtime, { recursive: true, force: true });
    report.privateRuntimeRemoved = true;
  } else {
    report.privateRuntimeRemoved = false;
    failed = true;
  }
  await writeFile(join(output, "direct-gtk-diagnostic.json"), JSON.stringify(report, null, 2));
}
if (failed) process.exitCode = 1;
