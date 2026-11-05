import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { createHash } from "node:crypto";
import os from "node:os";
import path from "node:path";
import { captureMcp } from "./capture-mcp.mjs";
import { downloadArtifacts } from "./capture-artifact-download.mjs";

test("MCP helper forwards generic and direct calls", async () => {
  const original = globalThis.fetch, calls = [];
  globalThis.fetch = async (url, request) => {
    calls.push({ url, headers: request.headers, body: JSON.parse(request.body) });
    return { json: async () => ({ result: { content: [{ text: JSON.stringify({ ok: true, value: { success: true } }) }] } }) };
  };
  try {
    const readiness = { port: 28420, token: "fixture-token" };
    assert.equal((await captureMcp(readiness, "example", { a: 1 })).success, true);
    assert.equal((await captureMcp(readiness, "direct", {}, false)).success, true);
    assert.equal(calls[0].body.params.name, "kelpie_extension");
    assert.equal(calls[0].body.params.arguments.name, "example");
    assert.equal(calls[1].body.params.name, "direct");
    assert.equal(calls[0].headers.authorization, "Bearer fixture-token");
  } finally { globalThis.fetch = original; }
});

test("artifact helper verifies ordered chunks and digest", async () => {
  const output = await mkdtemp(path.join(os.tmpdir(), "kelpie-artifact-helper-"));
  const bytes = Buffer.from("abcdef"), sha256 = createHash("sha256").update(bytes).digest("hex");
  const manifest = { id: "artifact", mimeType: "image/png", byteLength: bytes.length, sha256, partial: false, width: 1, height: 1 };
  const artifacts = [];
  const api = async (_method, request) => {
    const data = bytes.subarray(request.offset, Math.min(request.offset + 3, bytes.length));
    return { success: true, runId: "run", artifactId: "artifact", data: data.toString("base64"), offset: request.offset,
      nextOffset: request.offset + data.length, eof: request.offset + data.length === bytes.length,
      mimeType: manifest.mimeType, byteLength: bytes.length, sha256 };
  };
  try {
    await downloadArtifacts({ runId: "run", artifacts: [manifest] }, { api, output, artifacts });
    assert.deepEqual(await readFile(path.join(output, "artifact.png")), bytes);
    assert.deepEqual(artifacts, [{ runId: "run", ...manifest }]);
  } finally { await rm(output, { recursive: true, force: true }); }
});