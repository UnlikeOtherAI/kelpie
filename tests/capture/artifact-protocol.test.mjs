import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { inflateSync } from "node:zlib";
import { artifactProtocolPng, startArtifactProtocolFixture } from "./artifact-protocol-fixture.mjs";
import { verifyArtifactProtocols } from "./artifact-protocol.mjs";
const png = artifactProtocolPng();
const artifact = { id: "owned-png", byteLength: png.length, mimeType: "image/png",
  sha256: createHash("sha256").update(png).digest("hex") };
function fake(mutate = value => value) {
  const calls = [];
  const chunk = body => {
    const bytes = png.subarray(body.offset, body.offset + body.length);
    return mutate({ success: true, ...body, data: bytes.toString("base64"), nextOffset: body.offset + bytes.length,
      eof: body.offset + bytes.length === png.length, byteLength: png.length, mimeType: "image/png", sha256: artifact.sha256 });
  };
  return { calls, http: async (method, body) => { calls.push(method); return chunk(body); },
    mcp: async (name, args) => {
      calls.push(name);
      const body = name === "kelpie_extension" ? (assert.equal(args.name, "kelpie_get_script_artifact"), args.arguments) : args;
      return { jsonrpc: "2.0", result: { content: [{ type: "text", text: JSON.stringify({ ok: true, value: chunk(body) }) }] } };
    } };
}
test("large deterministic PNG reconstructs over three distinct protocol calls", async () => {
  assert.ok(png.length > 262144); assert.ok(png.equals(artifactProtocolPng()));
  const idatSize = png.readUInt32BE(33);
  assert.equal(png.subarray(37, 41).toString(), "IDAT");
  assert.equal(inflateSync(png.subarray(41, 41 + idatSize)).length, 512 * (512 * 3 + 1));
  const transport = fake();
  const result = await verifyArtifactProtocols({ runId: "owned-run", artifact, ...transport });
  assert.ok(result.bytes.equals(png)); assert.equal(result.report.protocols.length, 3);
  assert.ok(result.report.protocols.every(protocol => protocol.chunkCount > 1));
  assert.ok(transport.calls.includes("kelpie_extension")); assert.ok(transport.calls.includes("kelpie_get_script_artifact"));
});
test("truncation, digest, offset, EOF, MIME and base64 defects refuse", async () => {
  for (const change of [
    value => ({ ...value, data: value.data.slice(0, -4) }),
    value => ({ ...value, nextOffset: value.nextOffset + 1 }),
    value => ({ ...value, eof: !value.eof }),
    value => ({ ...value, mimeType: "video/mp4" }),
    value => ({ ...value, sha256: "a".repeat(64) }),
    value => ({ ...value, data: Buffer.alloc(Buffer.from(value.data, "base64").length, 0).toString("base64") }),
    value => ({ ...value, data: "!!!!" }),
  ]) await assert.rejects(verifyArtifactProtocols({ runId: "owned-run", artifact, ...fake(change) }));
  await assert.rejects(verifyArtifactProtocols({ runId: "owned-run", artifact: { ...artifact, byteLength: 100 }, ...fake() }));
});
test("read timeout terminates helper and signals caller", async () => {
  let signal;
  await assert.rejects(verifyArtifactProtocols({ runId: "owned-run", artifact, ...fake(),
    requestTimeoutMs: 10, totalTimeoutMs: 20, http: (_method, _body, options) => {
      signal = options.signal; return new Promise(() => {});
    } }), /timed out/);
  assert.equal(signal.aborted, true);
});
test("nonprivate PNG fixture serves a real bounded HTTP interface", async () => {
  const fixture = await startArtifactProtocolFixture();
  try {
    const page = await fetch(fixture.url); assert.match(await page.text(), /Nonprivate artifact protocol fixture/);
    const image = await fetch(fixture.url + "/noise.png");
    assert.equal(image.headers.get("content-type"), "image/png");
    assert.ok(Buffer.from(await image.arrayBuffer()).equals(png));
  } finally { await fixture.close(); }
});
