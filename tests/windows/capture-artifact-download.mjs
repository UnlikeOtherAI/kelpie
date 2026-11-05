import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { scriptArtifactSchema, scriptArtifactChunkSchema } from "../../packages/shared/dist/index.js";
export async function downloadArtifacts(run, { api, output, artifacts }) {
  assert.equal(typeof run.runId, "string");
  for (const raw of run.artifacts ?? []) {
    const manifest = scriptArtifactSchema.parse(raw);
    const chunks = []; let offset = 0;
    while (offset < manifest.byteLength) {
      const chunk = scriptArtifactChunkSchema.parse(await api("get-script-artifact", {
        runId: run.runId, artifactId: manifest.id, offset, length: 262144,
      }));
      assert.equal(chunk.runId, run.runId); assert.equal(chunk.artifactId, manifest.id);
      assert.equal(chunk.offset, offset); assert.equal(chunk.sha256, manifest.sha256);
      const bytes = Buffer.from(chunk.data, "base64");
      assert.equal(chunk.nextOffset, offset + bytes.length); assert.ok(bytes.length > 0);
      chunks.push(bytes); offset = chunk.nextOffset;
      assert.equal(chunk.eof, offset === manifest.byteLength);
    }
    const bytes = Buffer.concat(chunks);
    assert.equal(bytes.length, manifest.byteLength);
    assert.equal(createHash("sha256").update(bytes).digest("hex"), manifest.sha256);
    const extension = { "image/png": "png", "image/gif": "gif", "video/mp4": "mp4" }[manifest.mimeType];
    await writeFile(resolve(output, manifest.id + "." + extension), bytes);
    artifacts.push({ runId: run.runId, ...manifest });
  }
}
