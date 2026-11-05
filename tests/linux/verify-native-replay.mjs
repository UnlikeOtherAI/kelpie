#!/usr/bin/env node
// Independent artifact decode/pixel pass; no app, credentials, browser or GUI input.
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const execute = promisify(execFile), output = resolve(process.argv[2]);
const load = async name => JSON.parse(await readFile(join(output, name), "utf8"));
const media = await load("media-input.json"), launch = await load("launch-report.json");
assert.equal(media.source, launch.source);
for (const name of ["finalize-fault.json", "preinput-replacement.json"]) {
  try { media.artifacts.push(...(await load(name)).artifacts); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
}
try {
  const protocol = await load("artifact-protocol.json");
  media.artifacts.push({ ...protocol.artifact, runId: protocol.runId, file: join(output, "artifact-protocol.png") });
} catch (error) { if (error.code !== "ENOENT") throw error; }
for (const item of media.artifacts)
  assert.ok(resolve(item.file).startsWith(output + "/"), "Artifact path escapes the owned evidence directory");
const combined = join(output, "combined-media-input.json");
await writeFile(combined, JSON.stringify(media, null, 2));
const root = fileURLToPath(new URL("../../", import.meta.url));
const run = (script, args) => execute(process.execPath, [join(root, script), ...args],
  { timeout: 120000, maxBuffer: 2097152, env: process.env });
await run("tests/capture/verify-native-media.mjs", [combined, join(output, "all-frame-decode.json")]);
const runId = media.checks.find(check => check.name.startsWith("continuous "))?.detail?.runId;
assert.equal(typeof runId, "string");
const continuous = { ...media, artifacts: media.artifacts.filter(item => item.runId === runId) };
assert.ok(continuous.artifacts.some(item => item.mimeType === "image/gif"));
assert.ok(continuous.artifacts.some(item => item.mimeType === "video/mp4"));
const continuousPath = join(output, "continuous-media-input.json");
await writeFile(continuousPath, JSON.stringify(continuous, null, 2));
await run("tests/linux/verify-continuous-marker.mjs", [continuousPath, join(output, "continuous-marker-pixels.json")]);
const requireIDR=process.env.KELPIE_VERIFY_TERMINAL_IDR==="1";
if (requireIDR) await run("tests/linux/verify-terminal-idr.mjs", [continuousPath, join(output, "terminal-idr.json")]);
const report = { source: media.source, testSource: launch.testSource, binarySHA256: launch.binarySHA256,
  artifacts: media.artifacts.length, allFramesDecoded: true, continuousMarkerCenterAndFade: true, ...(requireIDR ? { terminalIDRVerified: true } : {}) };
await writeFile(join(output, "media-verification.json"), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report));
