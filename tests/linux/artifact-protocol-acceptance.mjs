import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { startArtifactProtocolFixture } from "../capture/artifact-protocol-fixture.mjs";
import { verifyArtifactProtocols } from "../capture/artifact-protocol.mjs";

/** Uses only the already-owned native app's exact authenticated socket. */
export async function runArtifactProtocolAcceptance(readiness, output, signal) {
  const origin = "http://127.0.0.1:" + readiness.port;
  const headers = { authorization: "Bearer " + readiness.token, "content-type": "application/json" };
  const request = async (path, body, callSignal) => {
    const response = await fetch(origin + path, {
      method: "POST", headers: path === "/mcp" ? { ...headers, accept: "application/json, text/event-stream" } : headers, body: JSON.stringify(body),
      signal: AbortSignal.any([signal, callSignal ?? AbortSignal.timeout(30000)]),
    });
    assert.equal(response.status, 200);
    return response.json();
  };
  const http = (method, body = {}, options = {}) => request("/v1/" + method, body, options.signal);
  let id = 0;
  const mcp = (method, body, options = {}) => request("/mcp", {
    jsonrpc: "2.0", id: ++id, method: "tools/call", params: { name: method, arguments: body },
  }, options.signal);
  const fixture = await startArtifactProtocolFixture();
  try {
    const tabs = await http("get-tabs");
    const tabId = tabs.tabs.find(tab => tab.active)?.id;
    assert.equal(typeof tabId, "string");
    assert.equal((await http("navigate", { tabId, url: fixture.url })).success, true);
    const run = await http("play-script", { version: 1, tabId, actions: [
      { action: "wait-ready", state: "complete" }, { action: "screenshot", name: "protocol-noise" },
    ] });
    assert.equal(run.success, true, JSON.stringify(run.error));
    const artifact = run.artifacts.find(item => item.mimeType === "image/png" && item.byteLength > 262 * 1024);
    assert.ok(artifact, "Native fixture PNG did not exceed262KiB");
    const verified = await verifyArtifactProtocols({ runId: run.runId, artifact, http, mcp });
    await writeFile(join(output, "artifact-protocol.png"), verified.bytes);
    const report = { source: process.env.KELPIE_CAPTURE_SOURCE, runId: run.runId, artifact, ...verified.report };
    await writeFile(join(output, "artifact-protocol.json"), JSON.stringify(report, null, 2));
    return report;
  } finally { await fixture.close(); }
}
