import assert from "node:assert/strict";
import { constants } from "node:fs";
import { readdir, lstat, open, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
import { waitFor } from "../windows/lib/http.mjs";
import { observeInFlight, awaitBounded } from "../windows/interactive-stop-lifecycle.mjs";

// Inject a collision only inside this launch's private synthetic output directory.
// This preserves an already-ACKed GIF prefix while MP4 publication must fail.
export async function runFinalizeFault(readiness, runtime, output) {
  const fixture = await startCaptureFixture();
  let pending;
  const api = async (method, body = {}) => {
    const response = await fetch("http://127.0.0.1:" + readiness.port + "/v1/" + method, {
      method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(30000),
    });
    const value = await response.json();
    if (response.status === 400) {
      assert.equal(value.success, false);
      assert.ok(typeof value.error?.code === "string" && value.error.code.length);
    } else assert.equal(response.status, 200);
    return value;
  };
  try {
    const tabs = (await api("get-tabs")).tabs;
    const tabId = tabs.find(tab => tab.active)?.id;
    assert.ok(tabId);
    const before = new Set(await readdir(runtime));
    pending = observeInFlight(api("play-script", { version: 1, tabId, actions: [
      { action: "navigate", url: fixture.url }, { action: "wait-ready", state: "complete" },
      { action: "click", target: { role: "button", name: "Confirm order", exact: true } },
      { action: "wait", ms: 2000 },
    ], capture: { formats: ["gif", "video"], fps: 5, maxWidth: 320, maxDurationMs: 20000, maxBytes: 4194304 } }));
    const event = await waitFor(() => fixture.events.find(event => event.type === "click" && event.target === "unique"),
      "trusted activation after movie ACK", 20000);
    assert.equal(event.trusted, true); assert.equal(event.hit, "unique");
    const directories = (await readdir(runtime)).filter(name => !before.has(name) && name.startsWith("kelpie-capture-"));
    assert.equal(directories.length, 1);
    const directory = join(runtime, directories[0]), identity = await lstat(directory);
    assert.ok(identity.isDirectory() && !identity.isSymbolicLink());
    assert.equal(identity.uid, process.getuid()); assert.equal(identity.mode & 0o777, 0o700);
    const collision = await open(join(directory, "capture.mp4"),
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    const collisionIdentity = await collision.stat();
    try { await collision.writeFile("synthetic finalization collision"); await collision.sync(); }
    finally { await collision.close(); }
    const result = await pending;
    assert.equal((await lstat(join(directory, "capture.mp4"))).ino, collisionIdentity.ino);
    assert.equal(await readFile(join(directory, "capture.mp4"), "utf8"), "synthetic finalization collision");
    assert.equal(result.success, false); assert.equal(result.error.code, "CAPTURE_FINALIZE_FAILED");
    assert.ok(result.artifacts.length > 0 && result.artifacts.every(item => item.partial));
    assert.ok(result.artifacts.some(item => item.mimeType === "image/gif"));
    assert.ok(!result.artifacts.some(item => item.mimeType === "video/mp4"));
    const status = await api("get-script-status", { runId: result.runId });
    assert.equal(status.success, true); assert.equal(status.state, "failed"); assert.equal(status.runSuccess, false);
    assert.equal(status.runError.code, "CAPTURE_FINALIZE_FAILED"); assert.equal(status.outputs, undefined);
    assert.ok(status.artifacts.length > 0 && status.artifacts.every(item => item.partial));
    const files = [];
    for (const artifact of result.artifacts) {
      const chunks = []; let offset = 0;
      while (offset < artifact.byteLength) {
        const chunk = await api("get-script-artifact", { runId: result.runId, artifactId: artifact.id, offset, length: 262144 });
        assert.equal(chunk.success, true); assert.equal(chunk.offset, offset);
        const bytes = Buffer.from(chunk.data, "base64");
        assert.ok(bytes.length && bytes.length <= 262144); chunks.push(bytes); offset += bytes.length;
        assert.equal(chunk.nextOffset, offset);
      }
      const bytes = Buffer.concat(chunks);
      assert.equal(bytes.length, artifact.byteLength);
      assert.equal(createHash("sha256").update(bytes).digest("hex"), artifact.sha256);
      const file = join(output, "finalize-" + artifact.id + ".gif");
      await writeFile(file, bytes); files.push({ ...artifact, runId: result.runId, file });
    }
    const recovery = await api("play-script", { version: 1, tabId, actions: [{ action: "wait", ms: 0 }] });
    assert.equal(recovery.success, true);
    const evidence = { source: process.env.KELPIE_CAPTURE_SOURCE, event, result: {
      runId: result.runId, success: false, code: result.error.code, inputGuarantee: result.inputGuarantee,
    }, status, artifacts: files, recoveryRun: recovery.runId };
    await writeFile(join(output, "finalize-fault.json"), JSON.stringify(evidence, null, 2));
    return { runId: result.runId, code: result.error.code, partialArtifacts: files.length, recovered: true };
  } finally {
    if (pending) await awaitBounded(pending, 5000).catch(() => {});
    await fixture.close();
  }
}
