#!/usr/bin/env node
// Launch an owned Linux headless app and reuse the canonical native HTTP/MCP corpus.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { control, waitFor } from "../windows/lib/http.mjs";
import { runFinalizeFault } from "./finalize-fault.mjs";
import { startBrowser, stopBrowser, fileExists } from "../windows/lib/process.mjs";


async function runCorpus(executable, args, env, signal) {
  const child = spawn(executable, args, { env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "", stderr = "", failure, killTimer;
  child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8");
  child.stdout.on("data", chunk => { stdout = (stdout + chunk).slice(-32768); });
  child.stderr.on("data", chunk => { stderr = (stderr + chunk).slice(-32768); });
  const cancel = () => {
    failure = new Error("Owned capture corpus cancelled");
    child.kill("SIGTERM");
    killTimer = setTimeout(() => child.kill("SIGKILL"), 1000);
  };
  const timer = setTimeout(() => {
    failure = new Error("Owned capture corpus exceeded its deadline"); child.kill("SIGKILL");
  }, 600000);
  signal.addEventListener("abort", cancel, { once: true });
  try {
    if (signal.aborted) cancel();
    const outcome = await new Promise((resolveExit, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolveExit({ code, signal }));
    });
    if (failure) throw failure;
    return { ...outcome, stdout, stderr };
  } finally {
    clearTimeout(timer); clearTimeout(killTimer);
    signal.removeEventListener("abort", cancel);
  }
}
assert.equal(process.platform, "linux");
const [binaryArg, outputArg] = process.argv.slice(2);
assert.ok(binaryArg && outputArg, "Provide exact native executable and fresh evidence directory");
assert.ok(process.env.KELPIE_CAPTURE_SOURCE, "Provide exact compiled source revision");
const executable = resolve(binaryArg), output = resolve(outputArg);
await mkdir(output, { recursive: false });
const runtime = await mkdtemp("/tmp/kelpie-capture-");
process.env.TMPDIR = runtime;
const profile = await mkdtemp(join(runtime, "profile-"));
const readinessPath = join(profile, "readiness.json");
const browser = startBrowser(executable, ["--headless", "--port", "0", "--profile-dir", profile,
  "--readiness-file", readinessPath, "--width", "1280", "--height", "900", "--url", "about:blank"]);
const report = {
  source: process.env.KELPIE_CAPTURE_SOURCE,
  binarySHA256: createHash("sha256").update(await readFile(executable)).digest("hex"),
  headless: true, runtime, profile, checks: [],
};
let readiness;
const cancellation = new AbortController();
const cancel = () => cancellation.abort();
process.once("SIGTERM", cancel); process.once("SIGINT", cancel);
try {
  readiness = await waitFor(async () => {
    if (cancellation.signal.aborted) throw new Error("Owned native launch cancelled");
    if (browser.child.exitCode !== null || browser.child.signalCode !== null)
      throw new Error("Owned app exited before readiness");
    try {
      const value = JSON.parse(await readFile(readinessPath, "utf8"));
      return typeof value.port === "number" && typeof value.token === "string" && value.token ? value : false;
    } catch (error) { if (error?.code === "ENOENT") return false; throw error; }
  }, "owned native readiness", 30000);
  const corpusPath = fileURLToPath(new URL("../windows/run-script-capture-acceptance.mjs", import.meta.url));
  const corpusOutput = join(output, "capture");
  const result = await runCorpus(process.execPath, [corpusPath, readinessPath, corpusOutput],
    { KELPIE_CAPTURE_PORT: String(readiness.port) }, cancellation.signal);
  report.corpus = { code: result.code, stdout: result.stdout, stderr: result.stderr };
  const corpus = JSON.parse(await readFile(join(corpusOutput, "report.json"), "utf8"));
  report.checks = corpus.checks;
  const extension = { "image/png": "png", "image/gif": "gif", "video/mp4": "mp4" };
  const media = { ...corpus, binarySHA256: report.binarySHA256, artifacts: corpus.artifacts.map(item => ({
    ...item, file: join(corpusOutput, item.id + "." + extension[item.mimeType]),
  })) };
  await writeFile(join(output, "media-input.json"), JSON.stringify(media, null, 2));
  assert.equal(result.code, 0, result.stderr || result.stdout);
  assert.ok(report.checks.length > 0 && report.checks.every(check => check.passed));
  if (process.env.KELPIE_LINUX_FINALIZE_FAULT === "1")
    report.finalizeFault = await runFinalizeFault(readiness, runtime, output);
} finally {
  try {
    if (browser.child.exitCode === null && browser.child.signalCode === null)
      await stopBrowser(browser, { gracefulClose: readiness ? () => control(readiness, "close-browser") : undefined, timeoutMs: 15000 });
    if (readiness) {
      assert.equal(browser.child.exitCode, 0);
      assert.equal(await fileExists(readinessPath), false);
      report.cleanup = "owned app exited and readiness removed";
    }
  } finally {
    process.off("SIGTERM", cancel); process.off("SIGINT", cancel);
    await writeFile(join(output, "launch-report.json"), JSON.stringify(report, null, 2));
    await writeFile(join(output, "app-logs.json"), JSON.stringify(browser.logs(), null, 2));
    // Synthetic profile stays available for recovery and evidence inspection.
    console.log(JSON.stringify({ output, checks: report.checks.length, cleanup: report.cleanup }));
  }
}
