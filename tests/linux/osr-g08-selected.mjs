// Opt-in installed OSR fixture; no raw app output or readiness token is retained.
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, realpath, rename, stat, writeFile } from "node:fs/promises";
import { isAbsolute, join, relative, sep } from "node:path";
import { promisify } from "node:util";

const execute = promisify(execFile);
const rows = profile => ["c", "s"].flatMap(curve => ["image/gif", "video/mp4"].map(mimeType =>
  ({ profile, curve, mimeType, status: "not-run" })));
export async function runSelectedG08({ readiness, binary, output, signal, invoke = execute }) {
  const source = process.env.KELPIE_CAPTURE_SOURCE, testSource = process.env.KELPIE_TEST_REVISION;
  assert.match(source ?? "", /^[a-f0-9]{40}$/);
  assert.match(testSource ?? "", /^[a-f0-9]{40}$/);
  const binarySHA256 = createHash("sha256").update(await readFile(binary)).digest("hex");
  const result = { version: 1, source, testSource, binarySHA256, runtime: "linux-osr-cef", results: [] };
  for (const profile of ["dense", "default"]) {
    const expected = rows(profile); result.results.push(...expected);
    const dir = join(output, profile), input = join(dir, "input.json"), analysis = join(dir, "analysis.json");
    try {
      await invoke(process.execPath, ["tests/linux/run-g08.mjs", readiness, binary, dir, "linux-osr-cef", profile],
        { signal, timeout: 120000, maxBuffer: 262144 });
      try {
        await invoke(process.execPath, [profile === "dense" ? "tests/capture/g08-verify.mjs" : "tests/linux/verify-g08-fast.mjs", input, analysis],
          { signal, timeout: 240000, maxBuffer: 262144 });
      } catch (error) { if (signal.aborted) throw error; }
      const parsed = JSON.parse(await readFile(analysis, "utf8"));
      assert.equal(parsed.results.length, 4);
      for (const row of expected) {
        const matches = parsed.results.filter(item => item.curve === row.curve && item.mimeType === row.mimeType);
        assert.equal(matches.length, 1);
        const item = matches[0];
        row.status = item.passed === true ? "passed" : item.confidence === "insufficient" ||
          /INSUFFICIENT_EVIDENCE|FAST_INSUFFICIENT_/.test(String(item.error ?? "")) ? "insufficient" : "failed";
        row.droppedFrames = Number.isSafeInteger(item.droppedFrames) && item.droppedFrames >= 0 ? item.droppedFrames : null;
        row.sha256 = /^[a-f0-9]{64}$/.test(item.sha256 ?? "") ? item.sha256 : null;
        const metric = profile === "dense" ? item.analysis : item.fit;
        const keys = profile === "dense" ? ["pointerRmsPx", "motionSamples", "maxMotionGapMs", "alphaRms", "wobbleRmsPx", "markerSamples"] :
          ["observedSpanMs", "intermediateSamples", "maximumGapMs", "fit350Px", "fit500Px"];
        row.metrics = Object.fromEntries(keys.filter(key => Number.isFinite(metric?.[key])).map(key => [key, metric[key]]));
      }
      const joined = JSON.parse(await readFile(input, "utf8"));
      assert.equal(joined.source, source);
      assert.equal(joined.testSource, testSource);
      assert.equal(joined.binarySHA256, binarySHA256);
      assert.equal(joined.runtime, "linux-osr-cef");
      assert.equal(joined.profile, profile);
      assert.equal(joined.eventsDropped, 0);
      assert.equal(joined.cases.length, 2);
      const root = await realpath(dir), validated = [], seen = new Set();
      for (const item of joined.cases) for (const artifact of item.artifacts) {
        assert.ok(["c", "s"].includes(item.curve) && ["image/gif", "video/mp4"].includes(artifact.mimeType));
        const key = item.curve + "/" + artifact.mimeType;
        assert.ok(!seen.has(key)); seen.add(key);
        const path = await realpath(artifact.file), rel = relative(root, path);
        assert.ok(rel && rel !== ".." && !rel.startsWith(".." + sep) && !isAbsolute(rel));
        const info = await stat(path);
        assert.ok(info.isFile() && info.size > 0 && info.size <= 33554432 && info.size === artifact.byteLength);
        assert.equal(createHash("sha256").update(await readFile(path)).digest("hex"), artifact.sha256);
        const row = expected.find(x => x.curve === item.curve && x.mimeType === artifact.mimeType);
        assert.equal(row.sha256, artifact.sha256);
        assert.ok(Array.isArray(artifact.timestamps) && artifact.timestamps.length > 0 && artifact.timestamps.length <= 800);
        assert.ok(artifact.timestamps.every((value, index) => Number.isFinite(value) && (index === 0 || value > artifact.timestamps[index - 1])));
        row.ptsSeconds = artifact.timestamps;
        assert.ok(Number.isSafeInteger(artifact.width) && artifact.width > 0 && Number.isSafeInteger(artifact.height) && artifact.height > 0);
        row.width = artifact.width; row.height = artifact.height; row.eventsDropped = 0;
        const events = ["warmup", "calibration", "start", "finish"].map(name => item.scene?.[name]);
        assert.ok(events.every(event => event && Number.isFinite(event.timeMs) &&
          Number.isFinite(event.center?.x) && Number.isFinite(event.center?.y) &&
          Number.isFinite(event.viewport?.width) && Number.isFinite(event.viewport?.height) &&
          event.trusted === true && typeof event.documentId === "string" && event.documentId.length > 0 && event.documentId.length <= 128));
        row.scene = events.map(event => ({ timeMs: event.timeMs, x: event.center.x, y: event.center.y,
          viewportWidth: event.viewport.width, viewportHeight: event.viewport.height, trusted: event.trusted }));
        row.sameDocument = events.every(event => event.documentId === events[0].documentId);
        assert.equal(row.sameDocument, true);
        validated.push({ path, hash: artifact.sha256, name: item.curve + (artifact.mimeType === "image/gif" ? ".gif" : ".mp4") });
      }
      assert.equal(validated.length, 4);
      const staging = join(dir, ".validated"), published = join(dir, "published");
      await mkdir(staging, { mode: 0o700 });
      for (const item of validated) {
        signal.throwIfAborted();
        const destination = join(staging, item.name);
        await copyFile(item.path, destination, 1);
        assert.equal(createHash("sha256").update(await readFile(destination)).digest("hex"), item.hash);
      }
      signal.throwIfAborted();
      await rename(staging, published);
    } catch (error) {
      if (signal.aborted) throw error;
      for (const row of expected) row.status = "failed";
    }
  }
  await writeFile(join(output, "safe-osr-g08.json"), JSON.stringify(result, null, 2) + "\n", { flag: "wx" });
  return result;
}
