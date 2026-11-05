import assert from "node:assert/strict";
import { constants } from "node:fs";
import { readdir, lstat, open, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { startReplacementFixture } from "../capture/replacement-fixture.mjs";
import { observeInFlight, awaitBounded } from "../windows/interactive-stop-lifecycle.mjs";
const execute = promisify(execFile);

/** Whitebox coordination reads only this owned run's pre-input PNG; public calls assert outcomes. */
export async function runPreinputReplacement(readiness, runtime, output, signal) {
  const fixture = await startReplacementFixture();
  const evidence = { source: process.env.KELPIE_CAPTURE_SOURCE, coordination: "owned critical PNG plus fixed fixture SSE",
    events: [], artifacts: [] };
  let pending;
  const api = async (method, body = {}) => {
    const response = await fetch("http://127.0.0.1:" + readiness.port + "/v1/" + method, {
      method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.any([signal, AbortSignal.timeout(30000)]),
    });
    const value = await response.json();
    if (response.status === 400) { assert.equal(value.success, false); assert.ok(value.error?.code); }
    else assert.equal(response.status, 200);
    return value;
  };
  const until = async (probe, name) => {
    const limit = Date.now() + 15000;
    while (Date.now() < limit) {
      if (signal.aborted) throw Error("Owned replacement probe aborted");
      const value = await probe(); if (value) return value;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw Error("Replacement setup deadline: " + name);
  };
  try {
    const tabId = (await api("get-tabs")).tabs.find(tab => tab.active)?.id;
    assert.equal((await api("navigate", { tabId, url: fixture.url })).success, true);
    const ready = await until(() => fixture.events.find(event => event.type === "ready"), "owned SSE document");
    const viewport = (await api("evaluate", { tabId, expression: "({width:innerWidth,height:innerHeight})" })).result;
    const before = new Set(await readdir(runtime));
    pending = observeInFlight(api("play-script", { version: 1, tabId,
      actions: [{ action: "click", target: { role: "link", name: "Next document", exact: true } }],
      capture: { formats: ["gif", "video", "screenshots"], fps: 1, maxWidth: 640, maxBytes: 8388608, maxDurationMs: 20000 },
      tapIndicator: { color: "#FF0000", radius: 24, durationMs: 700, wobble: false, fade: true } }));
    const png = await until(async () => {
      const names = (await readdir(runtime)).filter(name => !before.has(name) && name.startsWith("kelpie-capture-"));
      if (!names.length) return false;
      assert.equal(names.length, 1);
      const directory = join(runtime, names[0]), parent = await lstat(directory);
      assert.ok(parent.isDirectory() && !parent.isSymbolicLink() && parent.uid === process.getuid() && (parent.mode & 0o777) === 0o700);
      let handle;
      try {
        handle = await open(join(directory, "step-0.png"), constants.O_RDONLY | constants.O_NOFOLLOW);
        const info = await handle.stat();
        assert.ok(info.isFile() && info.uid === process.getuid() && !(info.mode & 0o077) && info.size <= 16777216);
        if (!info.size) return false;
        const bytes = await handle.readFile();
        if (bytes.length < 32 || bytes.subarray(-12, -4).toString("hex") !== "0000000049454e44") return false;
        assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
        return { bytes, device: info.dev, inode: info.ino };
      } catch (error) { if (error.code === "ENOENT") return false; throw error; }
      finally { await handle?.close(); }
    }, "complete private critical PNG");
    evidence.pngObservedBeforeSignal = true;
    fixture.replaceNext(ready.documentId);
    const replaced = await until(() => fixture.events.find(event => event.type === "replaced" && event.documentId === ready.documentId),
      "SSE replacement acknowledgement");
    assert.equal(replaced.oldConnected, false);
    const file = join(output, "preinput-critical.png"); await writeFile(file, png.bytes);
    const width = png.bytes.readUInt32BE(16), height = png.bytes.readUInt32BE(20), scale = width / viewport.width;
    const radius = Math.ceil(24 * scale + 4), cx = 230 * scale, cy = 180 * scale;
    const left = Math.floor(cx - radius), top = Math.floor(cy - radius), side = radius * 2 + 1;
    const decoded = await execute("ffmpeg", ["-v", "error", "-threads", "1", "-i", file,
      "-vf", "format=rgb24,crop=" + side + ":" + side + ":" + left + ":" + top + ":exact=1",
      "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], { encoding: "buffer", timeout: 5000, maxBuffer: 262144 });
    let red = 0;
    for (let index = 0; index < decoded.stdout.length; index += 3)
      if (decoded.stdout[index] > 190 && decoded.stdout[index + 1] < 130 && decoded.stdout[index + 2] < 130) red++;
    assert.ok(red > 60, "The critical PNG did not show the requested red marker");
    evidence.presentation = { width, height, device: png.device, inode: png.inode, redPixels: red,
      sha256: createHash("sha256").update(png.bytes).digest("hex"), file };

    const result = await pending;
    evidence.result = { runId: result.runId, success: result.success, code: result.error?.code, mayHaveCompleted: result.mayHaveCompleted };
    evidence.events = fixture.events.slice();
    const down = evidence.events.filter(event => event.type === "pointerdown");
    if (down.some(event => event.time <= replaced.time))
      throw Error("REPLACEMENT_SETUP_RACE: input preceded the observed mutation");
    assert.equal(down.length, 0, "Native pointerdown escaped after known target replacement");
    assert.ok(!evidence.events.some(event => event.type === "click"));
    assert.equal(result.success, false);
    assert.ok(["STALE_TARGET", "TARGET_MOVED", "TARGET_NOT_FOUND", "TARGET_OBSCURED"].includes(result.error?.code));
    assert.equal(result.mayHaveCompleted, false);
    assert.notEqual((await api("get-current-url", { tabId })).url, fixture.url + "/next");

    for (const item of result.artifacts ?? []) {
      const chunks = []; let offset = 0;
      while (offset < item.byteLength) {
        const chunk = await api("get-script-artifact", { runId: result.runId, artifactId: item.id, offset, length: 262144 });
        assert.equal(chunk.success, true); assert.equal(chunk.offset, offset);
        const bytes = Buffer.from(chunk.data, "base64");
        assert.ok(bytes.length); assert.equal(chunk.nextOffset, offset + bytes.length);
        chunks.push(bytes); offset = chunk.nextOffset;
      }
      const bytes = Buffer.concat(chunks); assert.equal(bytes.length, item.byteLength);
      assert.equal(createHash("sha256").update(bytes).digest("hex"), item.sha256);
      const extension = { "image/png": "png", "image/gif": "gif", "video/mp4": "mp4" }[item.mimeType];
      const file = join(output, "preinput-" + item.id + "." + extension); await writeFile(file, bytes);
      evidence.artifacts.push({ ...item, runId: result.runId, file });
    }
    assert.equal((await api("play-script", { version: 1, tabId, actions: [{ action: "wait", ms: 0 }] })).success, true);
    evidence.recovery = true;
    return evidence;
  } catch (error) { evidence.failure = error.message; throw error; }
  finally {
    if (pending) await awaitBounded(pending, 5000).catch(() => {});
    evidence.events = fixture.events.slice();
    await fixture.close();
    await writeFile(join(output, "preinput-replacement.json"), JSON.stringify(evidence, null, 2));
  }
}
