import assert from "node:assert/strict";
import { createHash } from "node:crypto";

const hash = bytes => createHash("sha256").update(bytes).digest("hex");
function unwrap(value) {
  if (value?.jsonrpc) {
    assert.equal(value.error, undefined, "Artifact JSON-RPC request failed");
    value = value.result;
  }
  if (Array.isArray(value?.content)) {
    assert.notEqual(value.isError, true, "Artifact MCP request failed");
    const text = value.content.filter(item => item.type === "text");
    assert.equal(text.length, 1, "Expected one structured MCP result");
    assert.ok(text[0].text.length <= 1_500_000, "MCP artifact response exceeds bound");
    value = JSON.parse(text[0].text);
  }
  if (typeof value?.ok === "boolean") {
    assert.equal(value.ok, true, "Artifact gateway request failed");
    value = value.value;
  }
  assert.equal(value?.success, true, "Artifact native request failed");
  return value;
}

/** Caller supplies already-owned, pinned authenticated transports; never attach or launch here. */
export async function verifyArtifactProtocols({
  runId, artifact, http, mcp, chunkLength = 262144, maxBytes = 16 * 1024 * 1024,
  requestTimeoutMs = 10000, totalTimeoutMs = 120000,
}) {
  assert.ok(typeof runId === "string" && runId.length <= 128);
  assert.equal(artifact.mimeType, "image/png", "Use the deterministic nonprivate PNG case");
  assert.ok(Number.isSafeInteger(artifact.byteLength) && artifact.byteLength > 262 * 1024,
    "PNG must exceed262KiB and the default256KiB chunk");
  assert.ok(artifact.byteLength <= maxBytes && maxBytes <= 32 * 1024 * 1024, "Artifact size exceeds test budget");
  assert.match(artifact.sha256, /^[a-f0-9]{64}$/);
  assert.ok(typeof artifact.id === "string" && artifact.id.length <= 128);
  assert.ok(Number.isInteger(chunkLength) && chunkLength >= 4096 && chunkLength <= 1048576);
  assert.ok(Number.isInteger(requestTimeoutMs) && requestTimeoutMs >= 10 && requestTimeoutMs <= 30000);
  assert.ok(Number.isInteger(totalTimeoutMs) && totalTimeoutMs >= requestTimeoutMs && totalTimeoutMs <= 120000);
  const deadline = Date.now() + totalTimeoutMs;
  const results = [], assembled = [];
  const transports = [
    ["http", (body, options) => http("get-script-artifact", body, options)],
    ["mcp-direct", (body, options) => mcp("kelpie_get_script_artifact", body, options)],
    ["mcp-generic", (body, options) => mcp("kelpie_extension", { name: "kelpie_get_script_artifact", arguments: body }, options)],
  ];
  for (const [protocol, call] of transports) {
    let offset = 0, count = 0;
    const parts = [];
    while (offset < artifact.byteLength) {
      assert.ok(++count <= 8192, "Artifact chunk count exceeds bound");
      const timeout = Math.min(requestTimeoutMs, deadline - Date.now());
      assert.ok(timeout > 0, "Artifact protocol test deadline exceeded");
      const controller = new AbortController(); let timer;
      let response;
      try {
        response = await Promise.race([
          Promise.resolve().then(() => call({ runId, artifactId: artifact.id, offset, length: chunkLength }, { signal: controller.signal })),
          new Promise((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(Error("Artifact request deadline exceeded")); }, timeout); }),
        ]);
      } catch { throw Error("Artifact protocol request failed or timed out"); }
      finally { clearTimeout(timer); }
      const chunk = unwrap(response);
      for (const [key, expected] of Object.entries({
        runId, artifactId: artifact.id, offset, mimeType: artifact.mimeType,
        byteLength: artifact.byteLength, sha256: artifact.sha256,
      })) assert.equal(chunk[key], expected, "Artifact chunk identity/metadata mismatch: " + key);
      assert.ok(typeof chunk.data === "string" && chunk.data.length <= Math.ceil(chunkLength / 3) * 4);
      const bytes = Buffer.from(chunk.data, "base64");
      assert.equal(bytes.toString("base64"), chunk.data, "Noncanonical chunk base64");
      assert.ok(bytes.length > 0 && bytes.length <= chunkLength, "Invalid decoded chunk length");
      assert.ok(offset + bytes.length <= artifact.byteLength, "Chunk exceeds artifact");
      assert.equal(chunk.nextOffset, offset + bytes.length, "Chunk offset did not advance exactly");
      assert.equal(chunk.eof, chunk.nextOffset === artifact.byteLength, "Incorrect EOF");
      parts.push(bytes); offset = chunk.nextOffset;
    }
    const bytes = Buffer.concat(parts);
    assert.equal(bytes.length, artifact.byteLength);
    assert.equal(hash(bytes), artifact.sha256, "Reassembled artifact digest mismatch");
    assert.equal(bytes.subarray(0, 8).toString("hex"), "89504e470d0a1a0a", "Not a PNG");
    if (assembled.length) assert.ok(bytes.equals(assembled[0]), "Protocols returned different bytes");
    assembled.push(bytes);
    results.push({ protocol, chunkCount: count, byteLength: bytes.length, sha256: hash(bytes), mimeType: "image/png" });
  }
  // No readiness/token/origin/owner material is retained in this credential-free report.
  return { report: { version: 1, protocols: results, identical: true }, bytes: assembled[0] };
}
