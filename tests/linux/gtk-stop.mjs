import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
import { observeInFlight, awaitBounded } from "../windows/interactive-stop-lifecycle.mjs";
import { readNativeIdentity } from "./native-lifecycle.mjs";
const execute = promisify(execFile);

/** Standard AT-SPI Stop on one pinned native GTK process; never focus or inject input. */
export async function runGtkStop({ readiness, identity, binary, hash, output, env, signal }) {
  assert.equal(env.GDK_BACKEND, "wayland");
  const fixture = await startCaptureFixture();
  const report = { source: process.env.KELPIE_CAPTURE_SOURCE, invocation: "standard AT-SPI Action.DoAction",
    display: "existing GNOME Wayland session; no compositor pixel claim", artifacts: [] };
  let pending;
  const api = async (method, body = {}) => {
    const response = await fetch("http://127.0.0.1:" + readiness.port + "/v1/" + method, {
      method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.any([signal, AbortSignal.timeout(40000)]),
    });
    const value = await response.json();
    if (response.status === 400) { assert.equal(value.success, false); assert.ok(value.error?.code); }
    else assert.equal(response.status, 200);
    return value;
  };
  const automate = async mode => {
    const script = fileURLToPath(new URL("./gtk-stop-automation.py", import.meta.url));
    const value = await execute("/usr/bin/python3", ["-B", script, String(identity.pid), binary, identity.startTicks, hash, mode],
      { env, signal, timeout: 6000, maxBuffer: 65536 });
    return JSON.parse(value.stdout);
  };
  const wait = async (probe, name, timeoutMs = 10000) => {
    const end = Date.now() + timeoutMs; let last;
    while (Date.now() < end) {
      if (signal.aborted) throw Error("GTK acceptance aborted");
      try { const value = await probe(); if (value) return value; } catch (error) { last = error; }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw Error(name + ": " + (last?.message ?? "not observed"));
  };
  try {
    report.window = await wait(() => automate("window"), "Owned GTK window showing");
    const tabId = (await api("get-tabs")).tabs.find(tab => tab.active)?.id;
    assert.equal((await api("navigate", { tabId, url: fixture.url })).success, true);
    assert.equal((await api("play-script", { version: 1, tabId, actions: [{ action: "wait-ready", state: "complete" }] })).success, true);
    pending = observeInFlight(api("play-script", { version: 1, tabId, actions: [
      { action: "click", target: { role: "button", name: "Confirm order", exact: true } },
      { action: "wait", ms: 30000 },
      { action: "click", target: { role: "button", name: "Confirm order", exact: true } },
    ], capture: { formats: ["gif", "video", "screenshots"], fps: 5, maxWidth: 640, maxBytes: 8388608, maxDurationMs: 40000 },
    pointer: { enabled: true, curve: "s", durationMs: 300, easing: "ease-in-out" },
    tapIndicator: { color: "#FF0000", radius: 24, durationMs: 5000, wobble: true, fade: true } }));
    report.event = await wait(() => fixture.events.find(event => event.type === "click" && event.target === "unique"),
      "Trusted native click after encoded marker admission", 20000);
    assert.equal(report.event.trusted, true);
    report.button = await wait(() => automate("inspect"), "Native Stop button showing");
    const current = await readNativeIdentity(identity.pid); assert.equal(current?.startTicks, identity.startTicks);
    const running = await api("get-script-status");
    assert.equal(running.playing, true); assert.equal(running.state, "running");
    report.action = await automate("invoke"); assert.equal(report.action.invoked, true);
    const result = await awaitBounded(pending, 10000);
    assert.equal(result.runId, running.runId); assert.equal(result.success, false);
    const status = await api("get-script-status", { runId: result.runId });
    assert.equal(status.success, true); assert.equal(status.playing, false);
    assert.equal(status.state, "aborted"); assert.equal(status.runSuccess, false);
    assert.equal(status.outputs, undefined); assert.equal(status.error, undefined);
    assert.ok(result.artifacts.length > 0 && result.artifacts.every(item => item.partial));
    assert.equal(fixture.events.filter(event => event.type === "click" && event.target === "unique").length, 1);
    report.result = { runId: result.runId, code: result.error?.code, actionsExecuted: result.actionsExecuted, mayHaveCompleted: result.mayHaveCompleted };
    report.status = status;
    for (const item of result.artifacts) {
      const chunks = []; let offset = 0;
      while (offset < item.byteLength) {
        const chunk = await api("get-script-artifact", { runId: result.runId, artifactId: item.id, offset, length: 262144 });
        assert.equal(chunk.success, true); assert.equal(chunk.offset, offset);
        const bytes = Buffer.from(chunk.data, "base64"); assert.ok(bytes.length);
        assert.equal(chunk.nextOffset, offset + bytes.length); chunks.push(bytes); offset = chunk.nextOffset;
      }
      const bytes = Buffer.concat(chunks); assert.equal(bytes.length, item.byteLength);
      assert.equal(createHash("sha256").update(bytes).digest("hex"), item.sha256);
      const ext = { "image/png": "png", "image/gif": "gif", "video/mp4": "mp4" }[item.mimeType];
      const file = join(output, "gtk-stop-" + item.id + "." + ext); await writeFile(file, bytes);
      report.artifacts.push({ ...item, runId: result.runId, file });
    }
    assert.equal((await api("play-script", { version: 1, tabId, actions: [{ action: "wait", ms: 0 }] })).success, true);
    report.recovered = true;
    return report;
  } catch (error) { report.failure = error.message; throw error; }
  finally {
    if (pending) await awaitBounded(pending, 5000).catch(() => {});
    await fixture.close();
    await writeFile(join(output, "gtk-stop.json"), JSON.stringify(report, null, 2));
  }
}
